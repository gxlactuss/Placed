import Foundation

enum SampleData {
    static let userName = "Khushi Shelke"
    static let targetRole = "Software Engineer"
    static let quizzesTaken = 24
    static let averageScore = 78
    static let interviewsTaken = 6

    static func questions(topic: QuizTopic, difficulty: QuizDifficulty) -> [SampleQuizQuestion] {
        allQuestions.map { question in
            var tagged = question
            tagged.topic = topic
            tagged.difficulty = difficulty
            return tagged
        }
    }

    static let allQuestions: [SampleQuizQuestion] = [
        SampleQuizQuestion(
            prompt: "Which page-replacement algorithm can exhibit Belady's anomaly, where adding more page frames increases the number of page faults?",
            options: [
                .init(letter: "A", text: "LRU (Least Recently Used)"),
                .init(letter: "B", text: "Optimal (OPT)"),
                .init(letter: "C", text: "FIFO (First In First Out)"),
                .init(letter: "D", text: "Clock (Second Chance)"),
            ],
            correctLetter: "C",
            concept: "Operating Systems",
            explanation: "FIFO can suffer Belady's anomaly because it ignores access recency. Stack algorithms such as LRU and OPT are provably immune."
        ),
        SampleQuizQuestion(
            prompt: "What is the average time complexity of searching for a key in a balanced binary search tree with n nodes?",
            options: [
                .init(letter: "A", text: "O(1)"),
                .init(letter: "B", text: "O(log n)"),
                .init(letter: "C", text: "O(n)"),
                .init(letter: "D", text: "O(n log n)"),
            ],
            correctLetter: "B",
            concept: "Data Structures",
            explanation: "A balanced BST keeps its height at O(log n), so each comparison discards half the remaining subtree."
        ),
        SampleQuizQuestion(
            prompt: "In dynamic programming, what distinguishes memoization from tabulation?",
            options: [
                .init(letter: "A", text: "Memoization is top-down and lazy; tabulation is bottom-up and eager"),
                .init(letter: "B", text: "Memoization uses less memory in every case"),
                .init(letter: "C", text: "Tabulation only works on tree-shaped problems"),
                .init(letter: "D", text: "There is no practical difference"),
            ],
            correctLetter: "A",
            concept: "Dynamic Programming",
            explanation: "Memoization recurses and caches results as they are needed. Tabulation fills a table iteratively from the base cases upward."
        ),
        SampleQuizQuestion(
            prompt: "Which traversal of a graph uses a queue and visits nodes in order of increasing distance from the source?",
            options: [
                .init(letter: "A", text: "Depth-first search"),
                .init(letter: "B", text: "Breadth-first search"),
                .init(letter: "C", text: "Topological sort"),
                .init(letter: "D", text: "Kruskal's algorithm"),
            ],
            correctLetter: "B",
            concept: "Graphs",
            explanation: "BFS explores level by level using a FIFO queue, which yields shortest paths on unweighted graphs."
        ),
        SampleQuizQuestion(
            prompt: "A deadlock requires four conditions to hold simultaneously. Which of these is NOT one of them?",
            options: [
                .init(letter: "A", text: "Mutual exclusion"),
                .init(letter: "B", text: "Hold and wait"),
                .init(letter: "C", text: "Circular wait"),
                .init(letter: "D", text: "Priority inversion"),
            ],
            correctLetter: "D",
            concept: "Operating Systems",
            explanation: "The Coffman conditions are mutual exclusion, hold and wait, no preemption, and circular wait. Priority inversion is a separate scheduling problem."
        ),
        SampleQuizQuestion(
            prompt: "Which normal form eliminates transitive dependencies on the primary key?",
            options: [
                .init(letter: "A", text: "First normal form"),
                .init(letter: "B", text: "Second normal form"),
                .init(letter: "C", text: "Third normal form"),
                .init(letter: "D", text: "Boyce-Codd normal form"),
            ],
            correctLetter: "C",
            concept: "Databases",
            explanation: "3NF requires that no non-key attribute depends transitively on the primary key."
        ),
        SampleQuizQuestion(
            prompt: "What does the TCP three-way handshake establish?",
            options: [
                .init(letter: "A", text: "Encryption keys for the session"),
                .init(letter: "B", text: "Synchronised sequence numbers on both sides"),
                .init(letter: "C", text: "The shortest route between hosts"),
                .init(letter: "D", text: "The maximum bandwidth available"),
            ],
            correctLetter: "B",
            concept: "Networking",
            explanation: "SYN, SYN-ACK and ACK exchange and acknowledge initial sequence numbers so both sides can order and detect loss."
        ),
        SampleQuizQuestion(
            prompt: "Which data structure gives O(1) average insertion, deletion and lookup by key?",
            options: [
                .init(letter: "A", text: "Hash table"),
                .init(letter: "B", text: "Sorted array"),
                .init(letter: "C", text: "Linked list"),
                .init(letter: "D", text: "Min-heap"),
            ],
            correctLetter: "A",
            concept: "Data Structures",
            explanation: "With a good hash function and bounded load factor, hash tables achieve O(1) expected time for all three operations."
        ),
        SampleQuizQuestion(
            prompt: "In the context of DP, what is the time complexity of the standard 0/1 knapsack solution for n items and capacity W?",
            options: [
                .init(letter: "A", text: "O(n log W)"),
                .init(letter: "B", text: "O(n + W)"),
                .init(letter: "C", text: "O(nW)"),
                .init(letter: "D", text: "O(2^n)"),
            ],
            correctLetter: "C",
            concept: "Dynamic Programming",
            explanation: "The table has n rows and W columns and each cell is filled in constant time, so it is pseudo-polynomial O(nW)."
        ),
        SampleQuizQuestion(
            prompt: "Which of these guarantees a cycle-free ordering of a directed graph's vertices?",
            options: [
                .init(letter: "A", text: "Topological sort"),
                .init(letter: "B", text: "Dijkstra's algorithm"),
                .init(letter: "C", text: "Union-find"),
                .init(letter: "D", text: "Binary search"),
            ],
            correctLetter: "A",
            concept: "Graphs",
            explanation: "A topological ordering exists precisely when the directed graph is acyclic, so producing one also proves acyclicity."
        ),
    ]

    static let companies: [CompanySummary] = [
        CompanySummary(slug: "google", name: "Google", questionCount: 100),
        CompanySummary(slug: "amazon", name: "Amazon", questionCount: 120),
        CompanySummary(slug: "meta", name: "Meta", questionCount: 90),
        CompanySummary(slug: "microsoft", name: "Microsoft", questionCount: 110),
    ]

    static let interviewOpener = "Let's start. Can you walk me through a project where you had to improve the performance of a system?"

    static let interviewFollowUps: [String] = [
        "Good. How did you decide what to cache, and how did you handle cache invalidation?",
        "Makes sense. What happened to your error rate and tail latency under peak load?",
        "Let's switch topics. Tell me about a time you disagreed with a teammate on a technical decision.",
        "Thanks, last one. How would you design a URL shortener that handles a billion redirects a day?",
    ]

    static let sampleTranscription = "In my final-year project the API was slow, so I added Redis caching and cut p95 latency from 800ms to 120ms."
}

struct SampleQuizQuestion: Identifiable {
    let id = UUID()
    var topic: QuizTopic = .csFundamentals
    var difficulty: QuizDifficulty = .medium
    let prompt: String
    let options: [Option]
    let correctLetter: String
    let concept: String
    let explanation: String

    struct Option: Identifiable {
        var id: String { letter }
        let letter: String
        let text: String
    }
}
