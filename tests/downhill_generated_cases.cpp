#include "downhill_leaf_handler.h"
#include "ps2x/iop/cdvd_iso_lookup.h"
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
uint64_t mix(uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31);
}
uint32_t transferPc;
unsigned handlerCalls;
struct HandlerTransfer {};
void copy(uint8_t *memory, R5900Context *ctx, PS2Runtime *) {
    ++handlerCalls;
    if (ctx->pc != getRegU32(ctx, 31)) throw std::runtime_error("continuation not established before handler");
    std::memcpy(memory + getRegU32(ctx, 4), memory + getRegU32(ctx, 5), getRegU32(ctx, 6));
    ctx->r[2] = ctx->r[4];
}
void transfer(uint8_t *memory, R5900Context *ctx, PS2Runtime *runtime) {
    copy(memory, ctx, runtime);
    ctx->pc = transferPc;
}
void yield(uint8_t *memory, R5900Context *ctx, PS2Runtime *runtime) {
    transfer(memory, ctx, runtime);
    throw HandlerTransfer{};
}
void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
void leafCase(uint64_t id, uint64_t seed, unsigned level) {
    std::array<uint8_t, 256> memory{}, expected{};
    const uint64_t bits = mix(seed ^ id);
    for (size_t i = 0; i < memory.size(); ++i) memory[i] = uint8_t(mix(bits + i));
    expected = memory;
    R5900Context ctx{};
    for (unsigned reg = 0; reg < 32; ++reg)
        ctx.r[reg] = _mm_set_epi64x(static_cast<int64_t>(mix(bits + reg)), static_cast<int64_t>(mix(bits - reg)));
    const uint32_t destination = 16u + uint32_t(bits % 64u);
    const uint32_t source = 144u + uint32_t((bits >> 8) % 64u);
    const uint32_t length = level == 0 ? uint32_t(bits % 4u) : uint32_t(bits % 33u);
    ctx.r[4] = _mm_set_epi64x(static_cast<int64_t>(bits), destination);
    ctx.r[5] = _mm_set_epi64x(static_cast<int64_t>(bits >> 1), source);
    ctx.r[6] = _mm_set_epi64x(static_cast<int64_t>(bits << 1), length);
    const uint32_t ra = uint32_t(id * 4u + 0x100000u);
    ctx.r[31] = _mm_set_epi64x(static_cast<int64_t>(bits), int64_t((bits & 0xffffffff00000000ULL) | ra));
    ctx.pc = uint32_t(bits);
    const R5900Context before = ctx;
    std::memcpy(expected.data() + destination, memory.data() + source, length);
    transferPc = uint32_t(mix(bits)) | 1u;
    handlerCalls = 0;
    const unsigned mode = unsigned((id / 2u) % 3u);
    bool thrown = false;
    try {
        if (mode == 0) downhill::leafHandler<copy>(memory.data(), &ctx, nullptr);
        else if (mode == 1) downhill::leafHandler<transfer>(memory.data(), &ctx, nullptr);
        else downhill::leafHandler<yield>(memory.data(), &ctx, nullptr);
    } catch (const HandlerTransfer &) { thrown = true; }
    require(thrown == (mode == 2), "handler transfer exception changed");
    require(handlerCalls == 1, "handler did not execute exactly once");
    require(memory == expected, "copy or guard bytes changed");
    require(ctx.pc == (mode == 0 ? ra : transferPc), "return/transfer PC changed");
    require(std::memcmp(&ctx.r[2], &before.r[4], sizeof(ctx.r[2])) == 0, "return value changed");
    for (unsigned reg = 0; reg < 32; ++reg)
        if (reg != 2) require(std::memcmp(&ctx.r[reg], &before.r[reg], sizeof(ctx.r[reg])) == 0, "unrelated register changed");
}

void le32(uint8_t *p, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) p[i] = uint8_t(value >> (i * 8));
}
size_t record(uint8_t *p, const std::string &name, uint32_t extent, uint32_t bytes, bool directory) {
    const size_t length = 33u + name.size() + (name.size() % 2u == 0u ? 1u : 0u);
    std::memset(p, 0, length);
    p[0] = uint8_t(length); p[25] = directory ? 2u : 0u; p[32] = uint8_t(name.size());
    le32(p + 2, extent); le32(p + 10, bytes);
    std::memcpy(p + 33, name.data(), name.size());
    return length;
}
void isoCase(uint64_t id, uint64_t seed, unsigned level) {
    const uint64_t bits = mix(seed ^ id);
    std::vector<uint8_t> image(26u * 2048u, 0u);
    auto *descriptor = image.data() + 16u * 2048u;
    descriptor[0] = 1; std::memcpy(descriptor + 1, "CD001", 5); descriptor[6] = 1;
    record(descriptor + 156, std::string(1, '\0'), 20u, 2048u, true);
    const std::string name = "F" + std::to_string(id) + ".BIN";
    const uint32_t fileExtent = 200u + uint32_t(bits % 5000u);
    const uint32_t fileSize = uint32_t(id + 1u); // Makes each fixture distinct, including negative cases.
    const unsigned depth = level == 0 ? 0u : (level == 1 ? 1u : 3u);
    std::string path = "cdrom0:/";
    for (unsigned i = 0; i < depth; ++i) {
        const std::string directory = "DIR" + std::to_string(i);
        record(image.data() + (20u + i) * 2048u, directory, 21u + i, 2048u, true);
        path += directory + "/";
    }
    auto *file = image.data() + (20u + depth) * 2048u;
    record(file, name + ";1", fileExtent, fileSize, false);
    path += name + ";1";
    bool expected = true, shortRead = false;
    const unsigned mode = unsigned((id / 2u) % 12u);
    switch (mode) {
    case 0: break;
    case 1:
        for (char &c : path) { if (c >= 'A' && c <= 'Z') c += 'a' - 'A'; if (c == '/') c = '\\'; }
        break;
    case 2: path += "/CHILD"; expected = false; break;
    case 3: path = "cdrom0:/../" + name; expected = false; break;
    case 4: descriptor[1] = 0; expected = false; break;
    case 5: shortRead = true; expected = false; break;
    case 6: file[0] = 33; expected = false; break;
    case 7: file[32] = file[0]; expected = false; break;
    case 8: file[25] = 0x80u; expected = false; break;
    case 9: file[1] = 1; expected = false; break;
    case 10: path.insert(path.rfind(';'), "_MISSING"); expected = false; break;
    case 11: le32(descriptor + 166, 32u * 1024u * 1024u + 1u); expected = false; break;
    }
    bool outOfBoundsRead = false;
    auto reader = [&](uint64_t offset, void *destination, size_t bytes) {
        if (offset > image.size() || bytes > image.size() - size_t(offset)) { outOfBoundsRead = true; return false; }
        if (shortRead && offset >= 20u * 2048u) return false;
        std::memcpy(destination, image.data() + size_t(offset), bytes);
        return true;
    };
    uint32_t extent = 0xdeadbeefu, size = 0xdeadbeefu;
    const bool found = ps2x::iop::lookupIsoFile(path, reader, extent, size);
    require(found == expected, "ISO accepted/rejected unexpected fixture");
    require(!outOfBoundsRead, "ISO attempted read outside fixture");
    if (expected) require(extent == fileExtent && size == fileSize, "ISO returned wrong physical extent/size");
    else require(extent == 0u && size == 0u, "failed lookup leaked stale outputs");
}
}

int main(int argc, char **argv) {
    uint64_t count = 1000, seed = 0xD0A11, first = 0;
    unsigned level = 0;
    try {
        if (argc != 5) throw std::runtime_error("usage: generated-cases COUNT SEED FIRST LEVEL");
        count = std::stoull(argv[1], nullptr, 0); seed = std::stoull(argv[2], nullptr, 0);
        first = std::stoull(argv[3], nullptr, 0); level = unsigned(std::stoul(argv[4]));
        if (!count || count > 10000000u || first > 10000000u - count || level > 2) throw std::runtime_error("invalid case range/level");
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 2; }
    uint64_t iso = 0, leaf = 0, completed = 0;
    for (uint64_t id = first; id < first + count; ++id) {
        try {
            if (id % 2u) { isoCase(id, seed, level); ++iso; }
            else { leafCase(id, seed, level); ++leaf; }
            ++completed;
        } catch (const std::exception &e) {
            std::cerr << "case=" << id << " seed=" << seed << " level=" << level << " family=" << (id % 2u ? "iso" : "leaf") << ": " << e.what() << '\n';
            std::cout << "{\"passed\":" << completed << ",\"failed\":1,\"failed_case\":" << id << ",\"seed\":" << seed << ",\"level\":" << level << "}\n";
            return 1;
        }
    }
    std::cout << "{\"passed\":" << completed << ",\"failed\":0,\"iso_cases\":" << iso << ",\"leaf_cases\":" << leaf << ",\"first_case\":" << first << ",\"seed\":" << seed << ",\"level\":" << level << "}\n";
}
