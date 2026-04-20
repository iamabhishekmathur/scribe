import Foundation

/// A meeting summary template defines the prompt style and sections for a specific meeting type.
public struct SummaryTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let description: String
    public let systemPrompt: String
    public let sections: [Section]

    public struct Section: Identifiable, Hashable, Sendable {
        public let id: String
        public let heading: String
        public let promptDirective: String
    }
}

// MARK: - Built-in Templates

extension SummaryTemplate {
    public static let all: [SummaryTemplate] = [general, oneOnOne, standup, customerCall, interview, brainstorm]

    public static func find(_ id: String) -> SummaryTemplate {
        all.first { $0.id == id } ?? .general
    }

    // MARK: General

    public static let general = SummaryTemplate(
        id: "general",
        name: "General",
        icon: "doc.text",
        description: "All-purpose meeting debrief",
        systemPrompt: """
        You are the user's executive assistant and chief of staff. You sat in on their meeting \
        and are now preparing a crisp debrief. Write like a sharp, trusted colleague — direct, \
        specific, and action-oriented. No filler. Use the user's own notes as signals for what \
        mattered most to them. Format your response in markdown.
        """,
        sections: [
            Section(id: "overview", heading: "Overview",
                    promptDirective: "2-3 sentences: what was this meeting about, who drove it, and what was the outcome."),
            Section(id: "key_points", heading: "Key Discussion Points",
                    promptDirective: "The substantive topics discussed. For each, note the conclusion or open question."),
            Section(id: "decisions", heading: "Decisions Made",
                    promptDirective: "Numbered list of concrete decisions. Include who made or owns each decision. If none were made, say so briefly."),
            Section(id: "action_items", heading: "Action Items",
                    promptDirective: "Numbered list. Each item must have: what needs to happen, who owns it, and any deadline mentioned. Pay special attention to the user's notes — anything they wrote down likely matters to them."),
            Section(id: "follow_ups", heading: "Follow-ups Needed",
                    promptDirective: "Things that weren't resolved and need follow-up. Include suggested next steps where obvious."),
        ]
    )

    // MARK: 1:1

    public static let oneOnOne = SummaryTemplate(
        id: "one_on_one",
        name: "1:1",
        icon: "person.2",
        description: "Manager/report or peer 1:1",
        systemPrompt: """
        You are summarizing a 1:1 meeting between two people. Focus on the relationship dynamics, \
        feedback exchanged in both directions, and personal/career growth topics. Be specific about \
        who said what. The user's notes indicate what mattered most to them. Format in markdown.
        """,
        sections: [
            Section(id: "updates", heading: "Updates Shared",
                    promptDirective: "What each person shared about their current work, progress, or status. Attribute to the speaker."),
            Section(id: "feedback", heading: "Feedback Exchanged",
                    promptDirective: "Any feedback given or received, in either direction. Quote or paraphrase specifically. Note tone (supportive, constructive, critical)."),
            Section(id: "blockers", heading: "Blockers & Challenges",
                    promptDirective: "Problems raised, frustrations expressed, or help requested. Include who raised each one."),
            Section(id: "growth", heading: "Career & Growth",
                    promptDirective: "Any discussion of career goals, skill development, role changes, or personal growth. If none, omit this section."),
            Section(id: "action_items", heading: "Action Items",
                    promptDirective: "What each person committed to do. Be specific about who owns what and any deadlines."),
        ]
    )

    // MARK: Standup

    public static let standup = SummaryTemplate(
        id: "standup",
        name: "Standup",
        icon: "person.3",
        description: "Daily standup or sync",
        systemPrompt: """
        You are summarizing a daily standup or team sync. Be extremely concise — bullet points only, \
        no prose. Group by person. The user's notes highlight what they care about. Format in markdown.
        """,
        sections: [
            Section(id: "done", heading: "Done (Yesterday)",
                    promptDirective: "What each person completed. Group by speaker name. One bullet per item, no elaboration."),
            Section(id: "today", heading: "Planned (Today)",
                    promptDirective: "What each person plans to work on. Group by speaker name. One bullet per item."),
            Section(id: "blockers", heading: "Blockers",
                    promptDirective: "Any blockers, dependencies, or things people are stuck on. Include who raised each one and who can help. If none, say \"No blockers raised.\""),
        ]
    )

    // MARK: Customer Call

    public static let customerCall = SummaryTemplate(
        id: "customer_call",
        name: "Customer Call",
        icon: "building.2",
        description: "Sales, support, or success call",
        systemPrompt: """
        You are summarizing an external customer-facing call. Focus on what the customer said, \
        their sentiment, what was promised or committed to, and any competitive intelligence. \
        Be precise about commitments — these may become contractual. The user's notes indicate \
        priority. Format in markdown.
        """,
        sections: [
            Section(id: "sentiment", heading: "Customer Sentiment",
                    promptDirective: "Overall tone of the customer: happy, frustrated, neutral, urgent. Support with 1-2 specific quotes or signals from the transcript."),
            Section(id: "pain_points", heading: "Pain Points & Needs",
                    promptDirective: "Problems the customer raised, features they need, or gaps they're experiencing. Be specific."),
            Section(id: "feature_requests", heading: "Feature Requests",
                    promptDirective: "Any specific product features, improvements, or capabilities the customer asked for. Include priority if mentioned."),
            Section(id: "commitments", heading: "Commitments Made",
                    promptDirective: "Anything promised or committed to by your team. Be precise — include who promised, what, and any timeline. These are important to track."),
            Section(id: "competitive", heading: "Competitive Intel",
                    promptDirective: "Any mention of competitors, alternative solutions, or comparisons. If none mentioned, omit this section."),
            Section(id: "follow_up", heading: "Follow-up Required",
                    promptDirective: "What needs to happen next, who owns it, and by when. Include both internal follow-ups and things promised to the customer."),
        ]
    )

    // MARK: Interview

    public static let interview = SummaryTemplate(
        id: "interview",
        name: "Interview",
        icon: "person.badge.plus",
        description: "Candidate interview debrief",
        systemPrompt: """
        You are summarizing a job interview. Focus on evaluating the candidate objectively. \
        Note specific examples and evidence, not just impressions. The user's notes are their \
        real-time reactions — weight them heavily. Format in markdown.
        """,
        sections: [
            Section(id: "strengths", heading: "Candidate Strengths",
                    promptDirective: "What the candidate demonstrated well. Cite specific answers, examples, or projects they mentioned."),
            Section(id: "concerns", heading: "Concerns",
                    promptDirective: "Areas of weakness, gaps, or red flags. Be specific about what raised the concern."),
            Section(id: "technical", heading: "Technical Assessment",
                    promptDirective: "How the candidate performed on technical questions or problem-solving. Note depth of knowledge, approach, and communication clarity."),
            Section(id: "culture", heading: "Culture & Communication",
                    promptDirective: "How the candidate communicates, collaborates, and fits with team culture. Note enthusiasm, curiosity, and self-awareness."),
            Section(id: "recommendation", heading: "Overall Lean",
                    promptDirective: "Based on the conversation, provide a brief lean: strong hire, hire, weak hire, weak no-hire, no-hire. Include 1-2 sentence rationale."),
            Section(id: "next_steps", heading: "Next Steps",
                    promptDirective: "Questions to explore in the next round, topics to dig deeper on, or logistics to follow up on."),
        ]
    )

    // MARK: Brainstorm

    public static let brainstorm = SummaryTemplate(
        id: "brainstorm",
        name: "Brainstorm",
        icon: "lightbulb",
        description: "Ideation or creative session",
        systemPrompt: """
        You are summarizing a brainstorm or ideation session. Capture ALL ideas — even half-formed \
        ones. Don't filter or judge. Distinguish between ideas that got energy/support and ones that \
        were parked. The user's notes highlight their favorites. Format in markdown.
        """,
        sections: [
            Section(id: "ideas", heading: "Ideas Generated",
                    promptDirective: "Every idea that came up, no matter how rough. Group related ideas together. Note who proposed each one."),
            Section(id: "selected", heading: "Ideas with Energy",
                    promptDirective: "Ideas that got positive reactions, were built upon, or that people seemed excited about. Note why they resonated."),
            Section(id: "parking_lot", heading: "Parking Lot",
                    promptDirective: "Ideas that were acknowledged but deferred, out of scope, or need more thought. Don't lose these."),
            Section(id: "next_steps", heading: "Next Steps",
                    promptDirective: "What was decided to do next with the top ideas. Who's exploring what. Any deadlines or check-ins planned."),
        ]
    )
}
