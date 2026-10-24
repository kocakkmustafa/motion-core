// Loopback SMTP stand-in for tests: speaks just enough submission protocol
// (EHLO, AUTH PLAIN, MAIL, RCPT, DATA, QUIT), records every command and the
// decoded message. Listens on 127.0.0.1 only.

export type FakeMail = {
  from: string;
  to: string;
  auth: string;
  headers: Record<string, string>;
  subject: string;
  text: string;
  raw: string;
};

export type FakeSmtpOptions = {
  /** Reply for AUTH; default 235 (accepted). */
  authReply?: string;
  /** When true the server accepts the socket but never greets. */
  silent?: boolean;
};

function decodeBase64(value: string): string {
  const bytes = Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function decodeWords(value: string): string {
  // Whitespace between adjacent encoded words is not part of the text.
  return value.replace(/\?=\s+=\?/g, "?==?").replace(
    /=\?UTF-8\?B\?([A-Za-z0-9+/=]*)\?=/g,
    (_, b64) => decodeBase64(b64),
  );
}

export class FakeSmtp {
  readonly mails: FakeMail[] = [];
  readonly commands: string[] = [];
  options: FakeSmtpOptions;
  #listener: Deno.Listener;
  #conns = new Set<Deno.Conn>();
  #done: Promise<void>;

  constructor(options: FakeSmtpOptions = {}) {
    this.options = options;
    this.#listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
    this.#done = this.#accept();
  }

  get port(): number {
    return (this.#listener.addr as Deno.NetAddr).port;
  }

  async close(): Promise<void> {
    this.#listener.close();
    for (const conn of this.#conns) {
      try {
        conn.close();
      } catch {
        // closed
      }
    }
    await this.#done.catch(() => {});
  }

  async #accept(): Promise<void> {
    const sessions: Promise<void>[] = [];
    try {
      for await (const conn of this.#listener) {
        this.#conns.add(conn);
        sessions.push(
          this.#session(conn).catch(() => {}).finally(() => {
            this.#conns.delete(conn);
          }),
        );
      }
    } catch {
      // listener closed
    }
    await Promise.all(sessions);
  }

  async #session(conn: Deno.Conn): Promise<void> {
    if (this.options.silent) {
      await conn.read(new Uint8Array(1)).catch(() => null);
      return;
    }
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const send = (line: string) => conn.write(encoder.encode(line + "\r\n"));
    let buffer = "";
    let auth = "";
    let from = "";
    let to = "";
    let inData = false;
    await send("220 fake.smtp ready");
    const chunk = new Uint8Array(4096);
    for (;;) {
      const read = await conn.read(chunk);
      if (read === null) return;
      buffer += decoder.decode(chunk.subarray(0, read), { stream: true });
      for (;;) {
        if (inData) {
          const end = buffer.indexOf("\r\n.\r\n");
          if (end < 0) break;
          const raw = buffer.slice(0, end).split("\r\n")
            .map((line) => (line.startsWith("..") ? line.slice(1) : line))
            .join("\r\n");
          buffer = buffer.slice(end + 5);
          inData = false;
          const split = raw.indexOf("\r\n\r\n");
          const head = raw.slice(0, split).replace(/\r\n /g, " ");
          const headers: Record<string, string> = {};
          for (const line of head.split("\r\n")) {
            const colon = line.indexOf(":");
            headers[line.slice(0, colon).toLowerCase()] = line.slice(colon + 1)
              .trim();
          }
          this.mails.push({
            from,
            to,
            auth,
            headers,
            subject: decodeWords(headers["subject"] ?? ""),
            text: decodeBase64(raw.slice(split + 4).replace(/\r\n/g, "")),
            raw,
          });
          await send("250 2.0.0 queued");
          continue;
        }
        const end = buffer.indexOf("\r\n");
        if (end < 0) break;
        const line = buffer.slice(0, end);
        buffer = buffer.slice(end + 2);
        this.commands.push(line.startsWith("AUTH ") ? "AUTH PLAIN ***" : line);
        if (line.startsWith("EHLO ")) {
          await send("250-fake.smtp");
          await send("250-AUTH PLAIN LOGIN");
          await send("250 8BITMIME");
        } else if (line.startsWith("AUTH PLAIN ")) {
          auth = decodeBase64(line.slice("AUTH PLAIN ".length));
          await send(this.options.authReply ?? "235 2.7.0 accepted");
        } else if (line.startsWith("MAIL FROM:")) {
          from = line.slice("MAIL FROM:".length);
          await send("250 2.1.0 ok");
        } else if (line.startsWith("RCPT TO:")) {
          to = line.slice("RCPT TO:".length);
          await send("250 2.1.5 ok");
        } else if (line === "DATA") {
          inData = true;
          await send("354 go ahead");
        } else if (line === "QUIT") {
          await send("221 2.0.0 bye");
          conn.close();
          return;
        } else {
          await send("502 5.5.2 unknown");
        }
      }
    }
  }
}
