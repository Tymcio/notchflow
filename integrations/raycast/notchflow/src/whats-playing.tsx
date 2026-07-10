import { Detail, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import { apiRequest, StatusResponse } from "./api";

export default function Command() {
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const data = await apiRequest<StatusResponse>("/v1/status");
        setStatus(data);
      } catch (err) {
        setError(String(err));
        await showToast({ style: Toast.Style.Failure, title: "Could not reach NotchFlow" });
      }
    })();
  }, []);

  if (error) {
    return <Detail markdown={`# NotchFlow unavailable\n\n${error}`} />;
  }

  if (!status) {
    return <Detail markdown="Loading…" />;
  }

  const playing = status.playing ? "Playing" : "Paused";
  return (
    <Detail
      markdown={`# ${status.title || "Not Playing"}\n\n**Status:** ${playing}\n\n**Premium:** ${status.premium ? "Yes" : "No"}`}
    />
  );
}
