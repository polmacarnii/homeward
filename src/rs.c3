module rs;

import gf256;
import std::io;

/* bytes de datos por bloque */
const int RS_K = 2;
/* bytes de redundancia por bloque */
const int RS_R = 2;
/* total de simbolos por bloque: n = k + r */
const int RS_N = RS_K + RS_R;
/* generador del campo; los puntos de evaluacion son alpha^i */
const char RS_ALPHA = 2;

fn int rs_encode(String input_path, String rd_path)
{
    char[RS_N] x;   /* puntos de evaluacion: x[i] = alpha^i */
    char[RS_K] buf; /* bloque de datos en curso */
    int blocks = 0; /* bloques procesados */

    for (int i = 0; i < RS_N; i++) {
        x[i] = gf256::inv(RS_ALPHA, i);
    }

    File? fin_opt = file::open(input_path, "rb");
    if (catch exc = fin_opt) {
        io::eprintfn("[RS] Error opening input file: %s", exc);
        return -1;
    }

    File fin = fin_opt;
    defer (void)fin.close();

    File? frd_opt = file::open(rd_path, "wb");
    if (catch exc = frd_opt) {
        io::eprintfn("[RS] Error opening redundancy file: %s", exc);
        return -1;
    }
    File frd = frd_opt;
    defer (void)frd.close();

    io::printfn("[RS ENCODE] Encoding %s -> %s", input_path, rd_path);

    while (true) {
        /* lee un bloque de datos; 0 significa fin de archivo */
        sz? n_read = fin.read(buf[..]);
        if (catch exc = n_read) {
            io::eprintfn("[RS] Error reading input file: %s", exc);
            return -1;
        }

        if (n_read == 0) break;

        /* el ultimo bloque puede quedar incompleto: se rellena con ceros */
        if (n_read < RS_K) {
            buf[1] = 0;
        }

        char d0 = buf[0];
        char d1 = buf[1];

        /* sindromes de los datos: valor y cuadrado evaluados en x0, x1 */
        char s1m = gf256::add(gf256::mul(d0, x[0]), gf256::mul(d1, x[1]));
        char s2m = gf256::add(gf256::mul(d0, gf256::mul(x[0], x[0])), gf256::mul(d1, gf256::mul(x[1], x[1])));

        /* resuelve el sistema 2x2 (Vandermonde en x2, x3) para p0, p1 */
        char x2 = x[2];
        char x3 = x[3];
        char det = gf256::add(gf256::mul(x2, gf256::mul(x3, x3)), gf256::mul(gf256::mul(x2, x2), x3));
        char det_inv = gf256::inv(det, -1);

        char det_p0 = gf256::add(gf256::mul(s1m, gf256::mul(x3, x3)), gf256::mul(s2m, x3));
        char p0 = gf256::mul(det_p0, det_inv);

        char det_p1 = gf256::add(gf256::mul(x2, s2m), gf256::mul(gf256::mul(x2, x2), s1m));
        char p1 = gf256::mul(det_p1, det_inv);

        char[RS_R] out_rd = {p0, p1};
        sz? written = frd.write(out_rd[..]);

        if (catch exc = written) {
            io::eprintfn("[RS] Error writing redundancy file: %s", exc);
            return -1;
        }

        blocks++;
    }

    io::printfn("[ENCODE] Done. Encoded %d block(s)", blocks);
    return 0;
}

fn int rs_fix(String corrupted_path, String rd_path, String output_path)
{
    char[RS_N] x;     /* puntos de evaluacion: x[i] = alpha^i */
    char[RS_K] dbuf;  /* bloque de datos (posiblemente con errores) */
    char[RS_R] rdbuf; /* redundancia correspondiente */
    int blocks = 0;    /* bloques escritos */
    int corrected = 0; /* bloques reparados */

    for (int i = 0; i < RS_N; i++) {
        x[i] = gf256::inv(RS_ALPHA, i);
    }

    File? fin_opt = file::open(corrupted_path, "rb");
    if (catch exc = fin_opt) {
        io::eprintfn("[RS] Error opening corrupted file: %s", exc);
        return -1;
    }
    File fin = fin_opt;
    defer (void)fin.close();

    File? frd_opt = file::open(rd_path, "rb");
    if (catch exc = frd_opt) {
        io::eprintfn("[RS] Error opening redundancy file: %s", exc);
        return -1;
    }
    File frd = frd_opt;
    defer (void)frd.close();

    File? fout_opt = file::open(output_path, "wb");
    if (catch exc = fout_opt) {
        io::eprintfn("[RS] Error opening output file: %s", exc);
        return -1;
    }
    File fout = fout_opt;
    defer (void)fout.close();

    io::printfn("[RS FIX] Fixing %s + %s -> %s", corrupted_path, rd_path,
                output_path);

    while (true) {
        sz nd = 0;
        sz nrd = 0;

        /* lee en paralelo la data y su redundancia */
        sz? nd_read = fin.read(dbuf[..]);
        if (catch exc = nd_read) {
            io::eprintfn("[RS] Error reading corrupted file: %s", exc);
            return -1;
        }
        nd = nd_read;

        /* bytes reales del bloque de datos: sin el relleno del ultimo
         * bloque parcial, para no agregar bytes de mas a la salida */
        sz out_len = nd;

        sz? nrd_read = frd.read(rdbuf[..]);
        if (catch exc = nrd_read) {
            io::eprintfn("[RS] Error reading redundancy file: %s", exc);
            return -1;
        }
        nrd = nrd_read;

        if (nd == 0 && nrd == 0) {
            break;
        }

        /* si un archivo termino antes que el otro, rellena con ceros */
        if (nd == 0) {
            dbuf[0] = 0;
            dbuf[1] = 0;
            nd = RS_K;
        }
        if (nrd == 0) {
            rdbuf[0] = 0;
            rdbuf[1] = 0;
            nrd = RS_R;
        }
        if (nd == 1) {
            dbuf[1] = 0;
        }

        if (nrd == 1) {
            rdbuf[1] = 0;
        }

        /* palabra recibida r = [d0 d1 p0 p1] y su copia corregible */
        char[RS_N] r = {dbuf[0], dbuf[1], rdbuf[0], rdbuf[1]};
        char[RS_N] r_corr = r;

        /* sindromes S1 = sum r[i]*x[i] y S2 = sum r[i]*x[i]^2 */
        char s1 = 0;
        char s2 = 0;
        for (int i = 0; i < RS_N; i++) {
            char xi = x[i];
            char xi2 = gf256::mul(xi, xi);
            s1 = gf256::add(s1, gf256::mul(r[i], xi));
            s2 = gf256::add(s2, gf256::mul(r[i], xi2));
        }

        /* sindrome no nulo: la palabra recibida esta danada, corregir */
        if (s1 != 0 || s2 != 0) {
            char s1_inv = gf256::inv(s1, -1);
            if (s1_inv != 0) {
                /* la posicion del error es donde x[j] == S2 / S1 */
                char x_j = gf256::mul(s2, s1_inv);
                int err_idx = -1;
                for (int i = 0; i < RS_N; i++) {
                    if (x[i] == x_j) {
                        err_idx = i;
                        break;
                    }
                }
                if (err_idx >= 0) {
                    /* magnitud del error: e = S1 / x[j] */
                    char xj_inv = gf256::inv(x_j, -1);
                    char e = gf256::mul(s1, xj_inv);
                    if (e != 0) {
                        /* en GF(2^8) restar es sumar (XOR) */
                        r_corr[err_idx] = gf256::add(r[err_idx], e);
                        corrected++;
                        io::printfn("[RS FIX] Block %d: corrected error at position %d", blocks, err_idx);
                    }
                }
            }
        }

        /* los RS_K primeros simbolos son los datos reparados */
        char[RS_K] obuf = {r_corr[0], r_corr[1]};
        sz? written = 0;
        if (out_len < RS_K) {
            /* el ultimo bloque es parcial: no escribir el relleno */
            written = fout.write(obuf[:out_len]);
        } else {
            written = fout.write(obuf[..]);
        }
        if (catch exc = written) {
            io::eprintfn("[RS] Error writing output file: %s", exc);
            return -1;
        }
        blocks++;
    }

    io::printfn("[RS FIX] Done. Processed %d block(s), corrected %d block(s)",
                blocks, corrected);
    return 0;
}
