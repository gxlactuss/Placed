import Foundation

/// A coarse grouping of LeetCode's ~75 topic tags, so "what does this company ask" reads as
/// a handful of study areas rather than a tag cloud.
enum TopicFamily: String, CaseIterable, Identifiable, Hashable, Sendable {
    case arrays, strings, twoPointers, linkedLists, stacks, trees, graphs
    case dynamicProgramming, greedy, binarySearch, heaps, recursion, math, design, sql

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrays: "Arrays & Hashing"
        case .strings: "Strings"
        case .twoPointers: "Two Pointers & Sliding Window"
        case .linkedLists: "Linked Lists"
        case .stacks: "Stacks & Queues"
        case .trees: "Trees"
        case .graphs: "Graphs"
        case .dynamicProgramming: "Dynamic Programming"
        case .greedy: "Greedy"
        case .binarySearch: "Binary Search"
        case .heaps: "Heaps"
        case .recursion: "Recursion & Backtracking"
        case .math: "Math & Bits"
        case .design: "Design"
        case .sql: "SQL"
        }
    }

    var shortTitle: String {
        switch self {
        case .arrays: "Arrays"
        case .twoPointers: "Two Pointers"
        case .stacks: "Stacks"
        case .dynamicProgramming: "DP"
        case .recursion: "Backtracking"
        case .math: "Math"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .arrays: "square.grid.3x1.below.line.grid.1x2"
        case .strings: "textformat.abc"
        case .twoPointers: "arrow.left.and.right"
        case .linkedLists: "link"
        case .stacks: "square.stack.3d.up"
        case .trees: "tree"
        case .graphs: "point.3.connected.trianglepath.dotted"
        case .dynamicProgramming: "tablecells"
        case .greedy: "bolt"
        case .binarySearch: "magnifyingglass"
        case .heaps: "triangle"
        case .recursion: "arrow.triangle.branch"
        case .math: "function"
        case .design: "square.on.square"
        case .sql: "cylinder.split.1x2"
        }
    }

    var rawTags: Set<String> {
        switch self {
        case .arrays:
            ["Array", "Hash Table", "Prefix Sum", "Counting", "Matrix", "Sorting", "Hash Function",
             "Bucket Sort", "Counting Sort", "Radix Sort", "Merge Sort", "Quickselect", "Sort",
             "Enumeration", "Simulation", "Quicksort"]
        case .strings:
            ["String", "String Matching", "Rolling Hash", "Trie", "Suffix Array", "Z Algorithm",
             "Knuth–Morris–Pratt Algorithm", "Boyer–Moore String-Search Algorithm", "Manacher"]
        case .twoPointers: ["Two Pointers", "Sliding Window"]
        case .linkedLists: ["Linked List", "Doubly-Linked List"]
        case .stacks: ["Stack", "Queue", "Monotonic Stack", "Monotonic Queue", "Bracket Sequences"]
        case .trees:
            ["Tree", "Binary Tree", "Binary Search Tree", "Segment Tree", "Binary Indexed Tree",
             "Lowest Common Ancestor", "Binary Lifting", "Treap", "Cartesian Tree"]
        case .graphs:
            ["Graph", "Graph Theory", "Depth-First Search", "Breadth-First Search", "Union-Find",
             "Union Find", "Topological Sort", "Shortest Path", "Minimum Spanning Tree",
             "Eulerian Circuit", "Strongly Connected Component", "Biconnected Component",
             "Directed Acyclic Graph", "Dijkstra's Algorithm", "Bipartite Graph", "Bidirectional Search",
             "0-1 BFS", "Flow Network", "Matching (Graph)", "Graph Coloring", "Eulerian Path",
             "Kosaraju's Algorithm", "Tarjan's SCC Algorithm", "Prim's Algorithm", "Kruskal's Algorithm",
             "Bellman–Ford Algorithm", "Floyd–Warshall Algorithm"]
        case .dynamicProgramming:
            ["Dynamic Programming", "Memoization", "Bitmask", "DP on Trees", "Knapsack Problem",
             "0-1 Knapsack", "Complete Knapsack", "Longest Increasing Subsequence",
             "Longest Common Subsequence"]
        case .greedy: ["Greedy"]
        case .binarySearch: ["Binary Search"]
        case .heaps: ["Heap (Priority Queue)", "Ordered Set"]
        case .recursion: ["Backtracking", "Recursion", "Divide and Conquer"]
        case .math:
            ["Math", "Bit Manipulation", "Number Theory", "Combinatorics", "Geometry",
             "Probability and Statistics", "Game Theory", "Brainteaser", "Randomized",
             "Reservoir Sampling", "Rejection Sampling", "Greatest Common Divisor", "Euclidean Algorithm",
             "Least Common Multiple", "Prime Factorization", "Primality Test", "Sieve Theory",
             "Prime Number Sieve", "Fermat's Little Theorem", "Pigeonhole Principle", "Polygons",
             "Minimax", "Zero-Sum Game"]
        case .design: ["Design", "Data Stream", "Iterator", "Concurrency", "Interactive", "Sweep Line"]
        case .sql: ["Database", "Shell"]
        }
    }

    /// Tags that sit on almost every problem. They only count when a problem has nothing more
    /// specific, otherwise every company would look "Array-heavy".
    private static let genericTags: Set<String> = [
        "Array", "String", "Hash Table", "Sorting", "Math", "Simulation", "Enumeration", "Counting", "Matrix",
    ]

    private static let familyByTag: [String: TopicFamily] = {
        var map: [String: TopicFamily] = [:]
        for family in allCases {
            for tag in family.rawTags { map[tag] = family }
        }
        return map
    }()

    /// Tags to filter a problem list by. Generic tags are left out so "Arrays" doesn't match
    /// every problem that happens to take an array.
    var filterTags: Set<String> {
        let specific = rawTags.subtracting(Self.genericTags)
        return specific.isEmpty ? rawTags : specific
    }

    /// Arrays & Hashing is the catch-all, so it is the least useful thing to call a weak spot.
    var isCatchAll: Bool { self == .arrays }

    static func families(for topics: [String]) -> Set<TopicFamily> {
        let specific = Set(topics.lazy.filter { !genericTags.contains($0) }.compactMap { familyByTag[$0] })
        if !specific.isEmpty { return specific }
        return Set(topics.compactMap { familyByTag[$0] })
    }
}

struct FamilyShare: Identifiable, Hashable, Sendable {

    enum Heat: Sendable { case hot, warm, normal }

    let family: TopicFamily
    /// Fraction of the company's most-asked questions, weighted by frequency.
    let share: Double
    /// `share` divided by the average company's share.
    let lift: Double

    var id: TopicFamily { family }

    /// 0 when asked at or below the average rate, rising to 1 at about 1.8× the average.
    /// Tiny topics are capped so a 3% topic never reads as red-hot.
    var temperature: Double {
        let t = min(max((lift - 0.8) / 1.0, 0), 1)
        return share < 0.05 ? min(t, 0.35) : t
    }

    var heat: Heat {
        if lift >= 1.5 && share >= 0.08 { return .hot }
        if lift >= 1.2 && share >= 0.05 { return .warm }
        return .normal
    }
}

struct CompanyProfile: Sendable {

    static let coreSize = 50
    static let smallSampleThreshold = 15

    /// nil for the across-all-companies profile.
    let companyName: String?
    let problemCount: Int
    /// Sorted by share, largest first, with empty families dropped.
    let families: [FamilyShare]
    let difficultyMix: [DSADifficulty: Double]
    /// The company's most-asked problems, by frequency.
    let core: [DSAProblem]

    var isGeneral: Bool { companyName == nil }
    var isSmallSample: Bool { !isGeneral && problemCount < Self.smallSampleThreshold }

    /// The families this company asks noticeably more than average, hottest first.
    var signature: [FamilyShare] {
        let hot = families.filter { $0.heat == .hot }
        let picks = hot.isEmpty ? families.filter { $0.heat == .warm } : hot
        return Array(picks.sorted { $0.share > $1.share }.prefix(2))
    }

    static func build(name: String, problems: [DSAProblem], baseline: [TopicFamily: Double]) -> CompanyProfile {
        let core = coreSet(of: problems)
        let shares = familyShares(in: core)
        let families = shares
            .filter { $0.value > 0 }
            .map { family, share in
                let average = baseline[family] ?? 0
                return FamilyShare(family: family, share: share, lift: average > 0 ? share / average : 1)
            }
            .sorted { $0.share > $1.share }

        var mix: [DSADifficulty: Double] = [:]
        for problem in core { mix[problem.difficulty, default: 0] += 1 }
        if !core.isEmpty {
            for key in mix.keys { mix[key, default: 0] /= Double(core.count) }
        }

        return CompanyProfile(
            companyName: name,
            problemCount: problems.count,
            families: families,
            difficultyMix: mix,
            core: core
        )
    }

    static func general(baseline: [TopicFamily: Double], difficultyMix: [DSADifficulty: Double]) -> CompanyProfile {
        CompanyProfile(
            companyName: nil,
            problemCount: 0,
            families: baseline
                .filter { $0.value > 0 }
                .map { FamilyShare(family: $0.key, share: $0.value, lift: 1) }
                .sorted { $0.share > $1.share },
            difficultyMix: difficultyMix,
            core: []
        )
    }

    static func coreSet(of problems: [DSAProblem]) -> [DSAProblem] {
        Array(
            problems.enumerated()
                .sorted { $0.element.frequency != $1.element.frequency
                    ? $0.element.frequency > $1.element.frequency
                    : $0.offset < $1.offset }
                .prefix(coreSize)
                .map(\.element)
        )
    }

    /// Each problem's weight is its frequency, split evenly across the families it belongs to.
    static func familyShares(in problems: [DSAProblem]) -> [TopicFamily: Double] {
        var weights: [TopicFamily: Double] = [:]
        for problem in problems {
            let families = TopicFamily.families(for: problem.topics)
            guard !families.isEmpty else { continue }
            let part = weight(of: problem) / Double(families.count)
            for family in families { weights[family, default: 0] += part }
        }
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return weights.mapValues { $0 / total }
    }

    static func weight(of problem: DSAProblem) -> Double { max(problem.frequency, 1) }
}

struct CompanyReadiness: Sendable {

    static let milestones = [25, 50, 75, 100]
    static let weakShareFloor = 0.08
    static let weakCoverageCeiling = 0.5

    /// Frequency-weighted share of the core set the user has solved, 0...1.
    let score: Double
    let solvedCount: Int
    let coreCount: Int
    /// How much of each family's core weight is solved, 0...1.
    let coverage: [TopicFamily: Double]
    /// Families that matter at this company but are mostly unsolved, worst first.
    let weakFamilies: [TopicFamily]
    let nextUp: [DSAProblem]

    var percent: Int { Int((score * 100).rounded(.down)) }

    var milestone: Int? { Self.milestones.last { percent >= $0 } }

    static func compute(profile: CompanyProfile, isSolved: (DSAProblem.ID) -> Bool) -> CompanyReadiness {
        var total = 0.0
        var solvedWeight = 0.0
        var solvedCount = 0
        var familyTotal: [TopicFamily: Double] = [:]
        var familySolved: [TopicFamily: Double] = [:]

        for problem in profile.core {
            let weight = CompanyProfile.weight(of: problem)
            let solved = isSolved(problem.id)
            total += weight
            if solved {
                solvedWeight += weight
                solvedCount += 1
            }
            let families = TopicFamily.families(for: problem.topics)
            guard !families.isEmpty else { continue }
            let part = weight / Double(families.count)
            for family in families {
                familyTotal[family, default: 0] += part
                if solved { familySolved[family, default: 0] += part }
            }
        }

        let coverage = Dictionary(uniqueKeysWithValues: familyTotal.map { family, weight in
            (family, familySolved[family, default: 0] / weight)
        })

        let weak = familyTotal
            .filter { family, weight in
                total > 0
                    && weight / total >= weakShareFloor
                    && coverage[family, default: 0] < weakCoverageCeiling
            }
            .sorted { lhs, rhs in
                if lhs.key.isCatchAll != rhs.key.isCatchAll { return rhs.key.isCatchAll }
                let lGap = lhs.value - familySolved[lhs.key, default: 0]
                let rGap = rhs.value - familySolved[rhs.key, default: 0]
                return lGap != rGap ? lGap > rGap : lhs.key.rawValue < rhs.key.rawValue
            }
            .map(\.key)

        let weakSet = Set(weak.prefix(2))
        let nextUp = profile.core
            .filter { !isSolved($0.id) }
            .enumerated()
            .sorted { lhs, rhs in
                let lWeak = !TopicFamily.families(for: lhs.element.topics).isDisjoint(with: weakSet)
                let rWeak = !TopicFamily.families(for: rhs.element.topics).isDisjoint(with: weakSet)
                if lWeak != rWeak { return lWeak }
                return lhs.offset < rhs.offset
            }
            .prefix(3)
            .map(\.element)

        return CompanyReadiness(
            score: total > 0 ? solvedWeight / total : 0,
            solvedCount: solvedCount,
            coreCount: profile.core.count,
            coverage: coverage,
            weakFamilies: Array(weak.prefix(2)),
            nextUp: Array(nextUp)
        )
    }

    /// "Weak on Graphs and DP", or nil when nothing stands out.
    var weakLine: String? {
        let names = weakFamilies.map(\.shortTitle)
        guard !names.isEmpty else { return nil }
        return "Weak on " + names.formatted(.list(type: .and))
    }
}

/// A one-line pointer from a mock DSA round back to the target company's weakest hot topic.
struct CompanyNudge {
    let company: String
    let topic: FamilyShare
    /// How much of that topic's most-asked weight the user has solved, 0...1.
    let coverage: Double
    let readiness: Int
}
