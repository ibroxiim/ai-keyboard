package com.ibrokhim.aikeyboard.data

/**
 * "Biroz qisqaroq qil" — what the user can ask of ✨ after seeing the variants, the way they would in a chat
 * with the model. Several can be on at once; every change asks for the variants again.
 */
enum class RewriteTweak(val label: String, val instruction: String) {
    SHORTER("qisqaroq", "shorter"),
    WARMER("iliqroq", "warmer and more affectionate"),
    FORMAL("rasmiyroq", "more formal and polite"),
    PLAYFUL("hazil", "playful, with light humour"),
}
