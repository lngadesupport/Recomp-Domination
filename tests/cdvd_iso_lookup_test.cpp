#include "ps2x/iop/cdvd_iso_lookup.h"
#include <fstream>
#include <iostream>
#include <cstring>

int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    std::ifstream iso(argv[1], std::ios::binary);
    auto reader = [&](uint64_t offset, void *data, size_t bytes) {
        iso.clear(); iso.seekg(offset); iso.read(static_cast<char *>(data), bytes);
        return static_cast<size_t>(iso.gcount()) == bytes;
    };
    for (const auto path : {"SKAT/DHSKAT.SKX", "MOD/CDVDSTM.IRX", "MOV/DHSCEAPR.PSS", "R/TSH.NGP"})
    {
        uint32_t lsn = 0, size = 0;
        if (!ps2x::iop::lookupIsoFile(std::string("cdrom0:\\") + path + ";1", reader, lsn, size))
            { std::cerr << "lookup failed: " << path << '\n'; return 1; }
        std::ifstream file(std::string(argv[2]) + "/" + path, std::ios::binary);
        file.seekg(0, std::ios::end);
        if (!file || file.tellg() != size) return 1;
        file.seekg(0);
        std::vector<uint8_t> actual(size), expected(size);
        file.read(reinterpret_cast<char *>(expected.data()), size);
        if (!reader(uint64_t(lsn) * 2048u, actual.data(), size) || actual != expected) return 1;
        std::cout << path << " extent=" << lsn << " bytes=" << size << " verified\n";
    }
    uint32_t lsn = 1, size = 1;
    if (ps2x::iop::lookupIsoFile("cdrom0:/../SKAT/DHSKAT.SKX", reader, lsn, size)) return 1;
    if (ps2x::iop::lookupIsoFile("cdrom0:/DOES_NOT_EXIST", reader, lsn, size)) return 1;
    auto badReader = [&](uint64_t offset, void *data, size_t bytes) {
        if (!reader(offset, data, bytes)) return false;
        if (offset == 16u * 2048u) static_cast<uint8_t *>(data)[1] = 0;
        return true;
    };
    if (ps2x::iop::lookupIsoFile("/SKAT/DHSKAT.SKX", badReader, lsn, size)) return 1;
    std::cout << "missing file, traversal, and invalid descriptor rejected\n";
}
