from fastapi import FastAPI

app = FastAPI(title="TODO_AI API")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
