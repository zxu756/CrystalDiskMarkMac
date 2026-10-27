#include "diskmark/config.h"

#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace {

int usage() {
    std::cerr << "usage: DiskMarkEngine --config <path>\n";
    return 2;
}

}  // namespace

int main(int argc, char** argv) {
    std::string configPath;
    for (int i = 1; i < argc; ++i) {
        const std::string argument = argv[i];
        if (argument == "--help") {
            std::cout << "usage: DiskMarkEngine --config <path>\n";
            return 0;
        }
        if (argument == "--config" && i + 1 < argc) {
            configPath = argv[++i];
            continue;
        }
        return usage();
    }

    if (configPath.empty()) {
        return usage();
    }

    std::ifstream input(configPath);
    if (!input) {
        std::cerr << "cannot open config: " << configPath << "\n";
        return 2;
    }

    std::stringstream buffer;
    buffer << input.rdbuf();

    try {
        const diskmark::Config config = diskmark::parseConfig(buffer.str());
        std::cout << "target=" << config.target
                  << " jobs=" << config.jobs.size()
                  << " fileSizeBytes=" << config.fileSizeBytes
                  << "\n";
        return 0;
    } catch (const diskmark::ConfigError& error) {
        std::cerr << error.code << ": " << error.what() << "\n";
        return 2;
    }
}
