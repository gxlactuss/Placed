import SwiftUI

struct InterviewRubricBreakdown: View {

    let rubric: RubricScores
    var revealed = true

    var body: some View {
        PPScoreBars(
            items: RubricDimension.allCases.map { dimension in
                .init(
                    id: dimension.rawValue,
                    title: dimension.title,
                    symbol: dimension.symbol,
                    score: rubric[dimension]
                )
            },
            revealed: revealed
        )
    }
}
