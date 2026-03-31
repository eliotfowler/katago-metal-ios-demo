import Foundation

/// Hardcoded mid-game positions for each board size.
/// Each position is ~30-50 moves in, formatted as "B D4 W F6 B C7 ..."
enum TestPositions {

    static func movesFor(boardSize: BoardSize) -> String {
        switch boardSize {
        case .nine:
            return position9x9
        case .thirteen:
            return position13x13
        case .nineteen:
            return position19x19
        }
    }

    // 9x9: ~35 moves from a teaching game
    // A balanced mid-game position with territory frameworks on both sides
    static let position9x9 = """
    B E5 W E7 B C5 W G5 B C7 W G7 B D3 W F3 B C3 W G3 \
    B B5 W H5 B B7 W H7 B D7 W F7 B D5 W F5 B E3 W E8 \
    B C4 W G4 B B3 W H3 B D8 W F8 B C8 W G8 B E4 W E6 \
    B D6 W F6 B D4 W F4 B C6 W G6 B B6 W H6
    """

    // 13x13: ~40 moves from a standard game
    // Opening through early middle game with some fighting
    static let position13x13 = """
    B D4 W K10 B D10 W K4 B G7 W J7 B D7 W K7 B G4 W G10 \
    B C6 W L8 B D8 W K6 B E3 W J11 B F10 W H4 B C10 W L4 \
    B B7 W M7 B E7 W J4 B F4 W H10 B C4 W L10 B G3 W G11 \
    B E11 W J3 B D11 W K3 B F3 W H11 B E5 W J9 B F9 W H5 \
    B C8 W L6 B D6 W K8
    """

    // 19x19: ~45 moves from a professional-style game
    // Standard opening with corner enclosures and an emerging fight
    static let position19x19 = """
    B Q16 W D4 B C16 W Q4 B D17 W R5 B F3 W C6 B O3 W P17 \
    B R14 W C10 B Q10 W G3 B K4 W D13 B N17 W R17 B R16 W S17 \
    B O16 W R10 B J16 W D10 B F17 W C14 B Q7 W H10 B L10 W N10 \
    B M10 W O10 B M9 W N9 B M11 W O11 B L9 W P9 B K10 W Q9 \
    B L11 W N11 B K9 W P10 B J10 W R8
    """
}
