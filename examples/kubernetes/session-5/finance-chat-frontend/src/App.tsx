import { useEffect, useRef, useState } from "react";
import "./App.css";
import { askQuestion, checkHealth, type AskResponse } from "./api";

interface ChatTurn {
  id: number;
  question: string;
  response?: AskResponse;
  error?: string;
}

const SUGGESTED_TOPICS = [
  "What is ROI?",
  "What is compound interest?",
  "Should I invest in Bitcoin?",
  "What is head and shoulders?",
  "What is support and resistance?",
];

type BackendStatus = "checking" | "online" | "offline";

function App() {
  const [question, setQuestion] = useState("");
  const [turns, setTurns] = useState<ChatTurn[]>([]);
  const [loading, setLoading] = useState(false);
  const [backendStatus, setBackendStatus] = useState<BackendStatus>("checking");
  const [modelName, setModelName] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    checkHealth()
      .then((health) => {
        setBackendStatus("online");
        setModelName(health.model);
      })
      .catch(() => setBackendStatus("offline"));
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [turns]);

  async function submitQuestion(rawQuestion: string) {
    const trimmed = rawQuestion.trim();
    if (!trimmed || loading) return;

    const id = Date.now();
    setTurns((prev) => [...prev, { id, question: trimmed }]);
    setQuestion("");
    setLoading(true);

    try {
      const response = await askQuestion(trimmed);
      setTurns((prev) =>
        prev.map((t) => (t.id === id ? { ...t, response } : t)),
      );
    } catch {
      setTurns((prev) =>
        prev.map((t) =>
          t.id === id
            ? { ...t, error: "Could not reach the API. Is it running on port 8000?" }
            : t,
        ),
      );
    } finally {
      setLoading(false);
    }
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    submitQuestion(question);
  }

  return (
    <div className="page">
      <header className="header">
        <div className="header-title">
          <h1>Finance Q&amp;A</h1>
          <p className="subtitle">spaCy + FastAPI, running CPU-only</p>
        </div>
        <div className={`status status-${backendStatus}`}>
          <span className="status-dot" />
          {backendStatus === "checking" && "Checking API..."}
          {backendStatus === "online" && `API online · ${modelName}`}
          {backendStatus === "offline" && "API offline"}
        </div>
      </header>

      <main className="chat">
        {turns.length === 0 && (
          <div className="empty-state">
            <p>Ask a finance question, or try one of these:</p>
            <div className="chip-row">
              {SUGGESTED_TOPICS.map((topic) => (
                <button
                  key={topic}
                  className="chip"
                  onClick={() => submitQuestion(topic)}
                  disabled={loading}
                >
                  {topic}
                </button>
              ))}
            </div>
          </div>
        )}

        {turns.map((turn) => (
          <div className="turn" key={turn.id}>
            <div className="bubble bubble-question">{turn.question}</div>

            {turn.error && (
              <div className="bubble bubble-error">{turn.error}</div>
            )}

            {turn.response && (
              <div className="bubble bubble-answer">
                <div className="answer-text">{turn.response.answer}</div>

                <div className="meta-row">
                  {turn.response.detected_term ? (
                    <span className="badge badge-term">
                      {turn.response.detected_term}
                    </span>
                  ) : (
                    <span className="badge badge-none">no match</span>
                  )}
                  {turn.response.entities.map((entity, i) => (
                    <span className="badge badge-entity" key={i}>
                      {entity.text} · {entity.label}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {!turn.response && !turn.error && (
              <div className="bubble bubble-answer bubble-loading">
                <span className="typing-dot" />
                <span className="typing-dot" />
                <span className="typing-dot" />
              </div>
            )}
          </div>
        ))}
        <div ref={bottomRef} />
      </main>

      <form className="composer" onSubmit={handleSubmit}>
        <input
          type="text"
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="e.g. What is compound interest?"
          disabled={loading || backendStatus === "offline"}
        />
        <button
          type="submit"
          disabled={loading || !question.trim() || backendStatus === "offline"}
        >
          Ask
        </button>
      </form>
    </div>
  );
}

export default App;
