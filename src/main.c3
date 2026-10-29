module main;

import std::io;
import gf256;
import rs;

fn void usage() {
    io::printfn("RS Codec (RS(4, 2) over GF(2^8))\n");
    io::printfn("Usage: ");
    io::printfn("    encode <input> <output.rd>");
    io::printfn("    fix <corrupted> <redundancy.rd> <output>");
}

fn int main(String[] args) {
    usz argc = args.len;

    if (argc < 3) {
        usage();
        return 1;
    }

    gf256::init();

    String cmd = args[1];

    if (cmd == "encode") {
        if (argc != 4) {
            usage();
            return 1;
        }

        int result = rs::rs_encode(args[2], args[3]);

        if (result == 0) {
            return 0;
        } else {
            return 1;
        }
    }

    if (cmd == "fix") {
        if (argc != 5) {
            usage();
            return 1;
        }

        int result = rs::rs_fix(args[2], args[3], args[4]);

        if (result == 0) {
            return 0;
        } else {
            return 1;
        }
    }
    usage();
    return 1;
}
