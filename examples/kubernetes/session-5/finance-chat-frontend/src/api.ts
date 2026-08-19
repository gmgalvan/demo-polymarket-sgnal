// Same-origin by default: in production nginx proxies /health, /ask and
// /queries straight to the backend Service (see nginx.conf.template), so
// the browser never needs to know the backend's address, and the backend
// never needs to be reachable from outside the cluster. Set VITE_API_URL
// only for local `npm run dev` if you want to point at a backend directly
// instead of going through nginx.
const API_URL = import.meta.env.VITE_API_URL ?? "";

export interface Entity {
  text: string;
  label: string;
}

export interface AskResponse {
  question: string;
  detected_term: string | null;
  answer: string;
  entities: Entity[];
}

export interface HealthResponse {
  status: string;
  model: string;
  hardware: string;
  database: string;
}

export async function checkHealth(): Promise<HealthResponse> {
  const res = await fetch(`${API_URL}/health`);
  if (!res.ok) {
    throw new Error(`Health check failed: ${res.status}`);
  }
  return res.json();
}

export async function askQuestion(question: string): Promise<AskResponse> {
  const res = await fetch(`${API_URL}/ask`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question }),
  });
  if (!res.ok) {
    throw new Error(`Request failed: ${res.status}`);
  }
  return res.json();
}
