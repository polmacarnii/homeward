/*
Galois Field GF(2^8) sobre el polinomio irreducible
f(x) = x^8 + x^4 + x^3 + x^2 + 1 (0x11D).

Cada elemento de un campo es un byte, las operaciones usan tablas
logaritmicas/exponenciales con generador alpha = 2, así que 
multiplicar o dividir se reduce a sumar y restar logaritmos mod 255
*/

module gf256;

char[512] gf_exp;
char[256] gf_log;

/* Debe llamarse solo una vez, antes de usar mul o inv */
fn void init() {
    uint x = 1; /* alpha^0 */

    /* el logaritmo de 0 no esta definido */
    gf_log[0] = 0;

    for (uint i = 0; i < 255; i++) {
        gf_exp[i] = (char)x;
        gf_log[(usz)x] = (char)i;

        /* Multiplicar por alpha en GF: desplazamiento a la izzquierda, y si se desborda el octavoo bit se reduce modulo 0x11D con un XOR */
        x = x << 1;
        if (x & 0x100) {
            x = x ^ 0x11D;
        }
    }

     /* como el periodo multiplicativo es 255, se repite el ciclo para cubrir todos los indices */
    for (uint i = 255; i < 512; i++) {
        gf_exp[i] = gf_exp[i - 255];
    }
}

/* a * b = alpha^(log(a) + log(b) mod 255) */
fn char mul(char a, char b) {
    if (a == 0 || b == 0) {
        return 0;
    }

    /* suma de logaritmos modulo 255 (el campo tiene 255 elementos) */
    int log_result = (int)gf_log[a] + (int)gf_log[b];

    if (log_result >= 255) {
        log_result = log_result - 255;
    }

    return gf_exp[log_result];
}

fn char add(char a, char b) {
    return a ^ b;
}

/* Calcula a^exp en GF mediante las tablas, con un exp reducido */
/* con exp >= 0 actua como potencia, con exp == -1 devuelve el inverso 
* multiplicativo, pues a^(-1) = a^(-1 mod 255) = a^256*/
fn char inv(char a, int exp) {
    if (a == 0) {
        return 0;
    }

    /* reduce el exponente al rango [0, 254] */
    int e = exp % 255;

    if (e < 0) {
        e = e + 255;
    }

    /* alpha^(log(a) * e mod 255) */
    int log_result = ((int)gf_log[a] * e) % 255;
    return gf_exp[log_result];
}
