"""Role-specific material for the technical interview round.

The client stores a role as its *title* on `User.target_role` — human wording,
because it is interpolated straight into prompts. This module recovers the role
from that string and supplies what a real interviewer for it would actually
probe.

Kept apart from `interview_prompts` because it grows along a different axis:
that module gains material when a *round* is added, this one when a *role* is.

Matching is deliberately loose (case and punctuation stripped) and returns
``None`` rather than raising, so a role this build doesn't know — free text from
an older account, or a title that has since been reworded — degrades to the
generic technical round instead of failing an interview.
"""

from __future__ import annotations

from enum import Enum


def _normalise(value: str) -> str:
    return "".join(ch for ch in value.lower() if ch.isalnum())


class CareerRole(str, Enum):
    """Mirrors the client's `CareerRole`. Keep the titles in step with it."""

    FRONTEND = "frontend"
    BACKEND = "backend"
    FULL_STACK = "full_stack"
    JAVA_SPRING = "java_spring"
    PYTHON = "python"
    FLUTTER = "flutter"
    REACT_NATIVE = "react_native"
    ANDROID = "android"
    IOS = "ios"
    CYBER_SECURITY = "cyber_security"
    DEVOPS = "devops"
    CLOUD = "cloud"
    DATA_SCIENCE = "data_science"
    MACHINE_LEARNING = "machine_learning"
    QA = "qa"
    EMBEDDED = "embedded"

    @classmethod
    def match(cls, stored: str | None) -> "CareerRole | None":
        """Recovers a role from whatever the account has stored."""
        if not stored or not stored.strip():
            return None
        target = _normalise(stored)
        for role in cls:
            if _normalise(_TITLES[role]) == target or role.value == target:
                return role
        return None


#: The exact wording the client persists. Changing one is safe for prompts but
#: orphans accounts holding the old string, which `match` absorbs loosely.
_TITLES: dict[CareerRole, str] = {
    CareerRole.FRONTEND: "Frontend Developer",
    CareerRole.BACKEND: "Backend Developer",
    CareerRole.FULL_STACK: "Full-Stack Web Developer",
    CareerRole.JAVA_SPRING: "Java / Spring Developer",
    CareerRole.PYTHON: "Python Developer",
    CareerRole.FLUTTER: "Flutter Developer",
    CareerRole.REACT_NATIVE: "React Native Developer",
    CareerRole.ANDROID: "Android Developer",
    CareerRole.IOS: "iOS Developer",
    CareerRole.CYBER_SECURITY: "Cyber Security Engineer",
    CareerRole.DEVOPS: "DevOps Engineer",
    CareerRole.CLOUD: "Cloud Engineer",
    CareerRole.DATA_SCIENCE: "Data Scientist",
    CareerRole.MACHINE_LEARNING: "Machine Learning Engineer",
    CareerRole.QA: "QA / Test Automation Engineer",
    CareerRole.EMBEDDED: "Embedded / IoT Engineer",
}


#: What a real interviewer for this role digs into, and the specific shallow
#: answer they would push past. Each entry is deliberately concrete: the whole
#: point of asking a student to pick a role is that "tell me about your tech
#: stack" becomes "why did you reach for a StateFlow rather than LiveData".
_TECHNICAL_BRIEFS: dict[CareerRole, str] = {
    CareerRole.FRONTEND: """\
Probe: how React (or their framework) actually re-renders and why a component re-rendered when they didn't expect it; keys in lists; state that should have been derived instead of stored; CSS layout with flexbox and grid, and why something overflowed; the event loop, and why a fetch resolved after a click handler finished; bundle size and what they did about it; accessibility beyond adding alt text; what breaks on a slow network or a small screen.
Push past: "React is fast because of the virtual DOM" — ask what the virtual DOM actually saves them, and when it doesn't.""",
    CareerRole.BACKEND: """\
Probe: how they designed an endpoint and what they would change; database indexes, and which query made them add one; N+1 queries; transactions and what isolation level they were on without realising; caching, invalidation, and what goes stale; idempotency for a retried payment; how they would find a slow request in production; queues, and what happens when a consumer dies mid-message.
Push past: "I used Redis for caching" — ask what they cached, how it is invalidated, and what a cache miss storm would do.""",
    CareerRole.FULL_STACK: """\
Probe: the seam between the two halves — how state on the client stays consistent with the database, what happens to a request that succeeds on the server but never reaches the browser, authentication across the boundary and where the token lives, why they chose server rendering or didn't, and how a deploy avoids breaking a client that hasn't reloaded.
Push past: a candidate who only ever answers from one side. If they keep retreating to the front end, ask a database question, and vice versa.""",
    CareerRole.JAVA_SPRING: """\
Probe: dependency injection and what Spring is actually doing at startup; bean scopes and when a singleton bit them; where @Transactional silently does nothing; JPA lazy loading and the N+1 it caused; equals and hashCode in an entity; checked versus unchecked exceptions and what they chose; the collections they picked and why; garbage collection only as far as it explains something they observed.
Push past: reciting the Spring annotation list — ask what one of them replaces if you delete it.""",
    CareerRole.PYTHON: """\
Probe: mutable default arguments and other places Python surprised them; list versus generator on a large dataset; the GIL, and specifically what it does and does not stop them doing; virtual environments and dependency conflicts; how they structured a Django or Flask project as it grew; the ORM query that turned out to be N+1; where they used async and whether it actually helped.
Push past: "Python is slow" — ask where, why, and what they did instead.""",
    CareerRole.FLUTTER: """\
Probe: the widget, element and render trees, and what setState actually rebuilds; const constructors and why they matter for rebuilds; their state management choice — Provider, Riverpod, Bloc — and why that one; keys, and the list bug that needed them; async in Dart and what an unawaited Future did; how they handled platform differences; jank, and how they diagnosed it.
Push past: "I used Bloc because it is scalable" — ask what specifically it scaled that setState would not have.""",
    CareerRole.REACT_NATIVE: """\
Probe: what actually crosses the bridge and why that is a cost; why a list stuttered and what FlatList tuning fixed it; navigation state and deep links; writing or wiring a native module; over-the-air updates and what cannot be shipped that way; platform-specific code and how much of it there was; how they debugged a release-only bug.
Push past: "It is write once, run anywhere" — ask what they had to write twice.""",
    CareerRole.ANDROID: """\
Probe: the activity and fragment lifecycle, and the bug that taught them it; configuration changes and what survived; ViewModel and why it exists; coroutines, scopes, and a leak they caused; LiveData versus StateFlow and why they moved; RecyclerView adapters and what they got wrong; Compose recomposition and what triggered an extra one; ANRs, memory leaks, and how they found them.
Push past: "I used MVVM" — ask what goes in the ViewModel and what does not, and why.""",
    CareerRole.IOS: """\
Probe: value versus reference semantics and where struct copying surprised them; ARC, retain cycles, and the closure that needed [weak self]; optionals beyond the syntax; SwiftUI's dependency tracking, and what @State, @StateObject and @Observable actually differ on; the main actor and what must run on it; why a list stuttered; Codable when the JSON did not match the model.
Push past: "I used SwiftUI because it is declarative" — ask what that bought them on a screen they actually built.""",
    CareerRole.CYBER_SECURITY: """\
Probe: the OWASP items they can explain rather than list; SQL injection and why parameterised queries fix it; XSS types and the correct defence for each; CSRF and why SameSite helps; how TLS establishes trust and what a certificate actually asserts; hashing versus encryption, and why bcrypt rather than SHA-256 for passwords; what they found in a CTF or an audit and how.
Push past: naming a tool. Ask what the tool reported and what they did about it.""",
    CareerRole.DEVOPS: """\
Probe: what their pipeline does between commit and production, and where it fails; Docker layers, image size, and what they cached; the difference between a container and a VM in terms that matter operationally; Kubernetes only as deep as they have really gone — pods, services, why a pod kept restarting; infrastructure as code and what drifted; what they actually alert on, and what they learned to stop alerting on; a rollback they had to perform.
Push past: "We use Kubernetes" — ask what it solved that a couple of servers would not have.""",
    CareerRole.CLOUD: """\
Probe: which services they used and what they would cost at ten times the traffic; VPCs, subnets, and why something could not reach the internet; IAM, and the over-broad policy they wrote first; the difference between availability and durability; what fails when a whole availability zone goes; managed database versus self-hosted and why; a bill that surprised them.
Push past: naming services. Ask what the service does that they would otherwise have had to build.""",
    CareerRole.DATA_SCIENCE: """\
Probe: the SQL they actually write — joins, window functions, and a query they had to optimise; how they cleaned a genuinely dirty dataset and what they threw away; correlation versus causation on their own project; picking a test and what its assumptions were; p-values, and what a non-significant result meant; how they would design an A/B test and how long they would run it; the chart they chose and why.
Push past: "I used pandas" — ask what the transformation was and why that shape.""",
    CareerRole.MACHINE_LEARNING: """\
Probe: bias and variance in terms of a model they trained; the metric they optimised and why accuracy was or was not it; how they split the data and whether anything leaked; regularisation and what overfitting looked like; why they chose that model over a simpler baseline, and whether the baseline was ever run; class imbalance; what happens to the model after deployment as the data drifts.
Push past: "I got 95% accuracy" — ask what the class balance was and what a naive predictor would have scored.""",
    CareerRole.QA: """\
Probe: how they decide what to test and what deliberately goes untested; equivalence partitioning and boundary values applied to something real; the flaky test and what they did about it; the test pyramid and where their suite actually sat; Selenium or Cypress waits, and why a sleep was the wrong fix; how tests run in CI and how long they take; a bug that escaped to production and what test would have caught it.
Push past: "We aim for 100% coverage" — ask what coverage does not tell them.""",
    CareerRole.EMBEDDED: """\
Probe: volatile, and the bug that required it; interrupt service routines and what must never happen inside one; stack versus heap on a device with kilobytes; the protocol they used — I2C, SPI, UART — and why that one; debouncing; an RTOS task priority problem or a race they hit; power consumption and what they did to reduce it; how they debugged without a console.
Push past: "I used an Arduino library" — ask what the library is doing to the register underneath.""",
}


def technical_brief(target_role: str | None) -> str | None:
    """Role-specific probing material for the technical round.

    ``None`` when the role isn't recognised, which leaves the generic brief in
    place rather than inventing specialisation for a role we know nothing about.
    """
    role = CareerRole.match(target_role)
    return _TECHNICAL_BRIEFS.get(role) if role else None
