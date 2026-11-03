import Foundation

enum CareerRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case frontend = "frontend"
    case backend = "backend"
    case fullStack = "full_stack"
    case javaSpring = "java_spring"
    case python = "python"
    case flutter = "flutter"
    case reactNative = "react_native"
    case android = "android"
    case ios = "ios"
    case cyberSecurity = "cyber_security"
    case devOps = "devops"
    case cloud = "cloud"
    case dataScience = "data_science"
    case machineLearning = "machine_learning"
    case qa = "qa"
    case embedded = "embedded"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontend: "Frontend Developer"
        case .backend: "Backend Developer"
        case .fullStack: "Full-Stack Web Developer"
        case .javaSpring: "Java / Spring Developer"
        case .python: "Python Developer"
        case .flutter: "Flutter Developer"
        case .reactNative: "React Native Developer"
        case .android: "Android Developer"
        case .ios: "iOS Developer"
        case .cyberSecurity: "Cyber Security Engineer"
        case .devOps: "DevOps Engineer"
        case .cloud: "Cloud Engineer"
        case .dataScience: "Data Scientist"
        case .machineLearning: "Machine Learning Engineer"
        case .qa: "QA / Test Automation Engineer"
        case .embedded: "Embedded / IoT Engineer"
        }
    }

    /// Tile label in the role picker. `title` is what gets stored and matched, so it stays as is.
    var shortTitle: String {
        switch self {
        case .frontend: "Frontend"
        case .backend: "Backend"
        case .fullStack: "Full-Stack Web"
        case .javaSpring: "Java / Spring"
        case .python: "Python"
        case .flutter: "Flutter"
        case .reactNative: "React Native"
        case .android: "Android"
        case .ios: "iOS"
        case .cyberSecurity: "Cyber Security"
        case .devOps: "DevOps"
        case .cloud: "Cloud"
        case .dataScience: "Data Science"
        case .machineLearning: "Machine Learning"
        case .qa: "QA & Automation"
        case .embedded: "Embedded & IoT"
        }
    }

    var blurb: String {
        switch self {
        case .frontend: "React, CSS, the browser, accessibility"
        case .backend: "APIs, databases, caching, scaling"
        case .fullStack: "Both ends, plus how they meet"
        case .javaSpring: "Core Java, Spring Boot, JPA, the JVM"
        case .python: "Django or Flask, the data model, the runtime"
        case .flutter: "Dart, widgets, state management"
        case .reactNative: "JS bridge, navigation, native modules"
        case .android: "Kotlin, lifecycle, Jetpack, Compose"
        case .ios: "Swift, SwiftUI, memory, concurrency"
        case .cyberSecurity: "Attacks, defences, crypto, networks"
        case .devOps: "CI/CD, containers, Kubernetes, observability"
        case .cloud: "AWS or Azure, networking, cost, availability"
        case .dataScience: "Statistics, SQL, pandas, experiments"
        case .machineLearning: "Models, training, evaluation, deployment"
        case .qa: "Test design, Selenium, automation, CI"
        case .embedded: "C, RTOS, microcontrollers, protocols"
        }
    }

    /// SF Symbols, all available on iOS 17.
    var icon: String {
        switch self {
        case .frontend: "paintbrush.pointed"            // building what users see
        case .backend: "server.rack"
        case .fullStack: "square.3.layers.3d"            // every layer of the stack
        case .javaSpring: "cup.and.saucer"               // Java's coffee cup
        case .python: "terminal"                         // scripts and the REPL
        case .flutter: "bird"                            // Dash, Flutter's mascot
        case .reactNative: "atom"                        // React's logo
        case .android: "smartphone"
        case .ios: "swift"
        case .cyberSecurity: "lock.shield"
        case .devOps: "infinity"                         // the DevOps loop
        case .cloud: "cloud"
        case .dataScience: "chart.dots.scatter"
        case .machineLearning: "brain"
        case .qa: "ladybug"                              // bug hunting
        case .embedded: "cpu"
        }
    }

    var family: Family {
        switch self {
        case .frontend, .backend, .fullStack, .javaSpring, .python: .software
        case .flutter, .reactNative, .android, .ios: .mobile
        case .cyberSecurity, .devOps, .cloud, .qa, .embedded: .infrastructure
        case .dataScience, .machineLearning: .data
        }
    }

    enum Family: String, CaseIterable, Identifiable {
        case software, mobile, data, infrastructure

        var id: String { rawValue }

        var title: String {
            switch self {
            case .software: "Software & Web"
            case .mobile: "Mobile"
            case .data: "Data & AI"
            case .infrastructure: "Infrastructure & Security"
            }
        }

        var roles: [CareerRole] { CareerRole.allCases.filter { $0.family == self } }
    }

    init?(title stored: String?) {
        guard let stored, !stored.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let normalised = Self.normalise(stored)
        guard let match = CareerRole.allCases.first(where: {
            Self.normalise($0.title) == normalised || $0.rawValue == normalised
        }) else { return nil }
        self = match
    }

    private static func normalise(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

enum RoleQuizGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case webFrontend = "web_frontend"
    case backendWeb = "backend_web"
    case javaSpring = "java_spring"
    case python = "python"
    case mobile = "mobile"
    case cyberSecurity = "cyber_security"
    case devopsCloud = "devops_cloud"
    case dataML = "data_ml"
    case qa = "qa"
    case embedded = "embedded"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webFrontend: "Frontend Web"
        case .backendWeb: "Backend & Full-Stack"
        case .javaSpring: "Java & Spring"
        case .python: "Python"
        case .mobile: "Mobile Development"
        case .cyberSecurity: "Cyber Security"
        case .devopsCloud: "DevOps & Cloud"
        case .dataML: "Data Science & ML"
        case .qa: "QA & Test Automation"
        case .embedded: "Embedded & IoT"
        }
    }
}

extension CareerRole {
    var quizGroup: RoleQuizGroup {
        switch self {
        case .frontend: .webFrontend
        case .backend, .fullStack: .backendWeb
        case .javaSpring: .javaSpring
        case .python: .python
        case .flutter, .reactNative, .android, .ios: .mobile
        case .cyberSecurity: .cyberSecurity
        case .devOps, .cloud: .devopsCloud
        case .dataScience, .machineLearning: .dataML
        case .qa: .qa
        case .embedded: .embedded
        }
    }
}
