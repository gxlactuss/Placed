-- SQLite Database Schema for "placed"
-- Foreign Key support must be enabled per connection in SQLite
PRAGMA foreign_keys = ON;

-- 1. Company
CREATE TABLE IF NOT EXISTS Company (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    is_kjsit_recruiter BOOLEAN NOT NULL DEFAULT 0
);

-- 2. Problem
CREATE TABLE IF NOT EXISTS Problem (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    slug TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    difficulty TEXT NOT NULL,
    url TEXT
);

-- 3. CompanyProblem (Join Table)
CREATE TABLE IF NOT EXISTS CompanyProblem (
    company_id INTEGER NOT NULL,
    problem_id INTEGER NOT NULL,
    topics TEXT,
    PRIMARY KEY (company_id, problem_id),
    FOREIGN KEY (company_id) REFERENCES Company (id) ON DELETE CASCADE,
    FOREIGN KEY (problem_id) REFERENCES Problem (id) ON DELETE CASCADE
);

-- 4. Quiz
CREATE TABLE IF NOT EXISTS Quiz (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    category TEXT,
    difficulty TEXT,
    questions_to_pass INTEGER
);

-- 5. Question
CREATE TABLE IF NOT EXISTS Question (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quiz_id INTEGER NOT NULL,
    prompt TEXT NOT NULL,
    correct_option_id TEXT,
    FOREIGN KEY (quiz_id) REFERENCES Quiz (id) ON DELETE CASCADE
);

-- 6. Option
CREATE TABLE IF NOT EXISTS Option (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL,
    label TEXT,
    text TEXT NOT NULL,
    FOREIGN KEY (question_id) REFERENCES Question (id) ON DELETE CASCADE
);

-- 7. Submission
CREATE TABLE IF NOT EXISTS Submission (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    quiz_id INTEGER NOT NULL,
    score INTEGER NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (quiz_id) REFERENCES Quiz (id) ON DELETE CASCADE
);

-- Indexes for foreign key lookups and common queries
CREATE INDEX IF NOT EXISTS idx_company_problem_problem_id ON CompanyProblem(problem_id);
CREATE INDEX IF NOT EXISTS idx_question_quiz_id ON Question(quiz_id);
CREATE INDEX IF NOT EXISTS idx_option_question_id ON Option(question_id);
CREATE INDEX IF NOT EXISTS idx_submission_quiz_id ON Submission(quiz_id);
CREATE INDEX IF NOT EXISTS idx_submission_user_id ON Submission(user_id);
