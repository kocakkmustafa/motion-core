// Minimal SMTP submission client for one plain-text message (Google Workspace
// on smtp.gmail.com:465, implicit TLS). Supabase Edge blocks outbound 25 and
// 587, so STARTTLS submission is not used. No dependency, no logging: the
// password, addresses and body never reach a log line or an error message.
// Callers get a secret-free outcome (failure class, protocol stage, reply
// code) from submitSmtpMail and decide what to log.

export type SmtpTls = "implicit" | "none";

export type SmtpConfig = {
  host: string;
  port: number;
  user: string;
  password: string;
  tls: SmtpTls;
  /** RFC 5322 From, e.g. `Motion <no-reply@yulalab.com>`. */
  from: string;
};

export type SmtpMessage = { to: string; subject: string; text: string };

/** Secret-free failure class: safe to log. */
export type SmtpFailure =
  | "config"
  | "network"
  | "auth"
  | "sender"
  | "recipient"
  | "message";

/** Where the submission stopped. */
export type SmtpStage =
  | "config"
  | "connect"
  | "greeting"
  | "ehlo"
  | "auth"
  | "mail_from"
  | "rcpt"
  | "data"
  | "message";

/** `code` is the server's three-digit reply when it answered; never text. */
export type SmtpOutcome =
  | { ok: true }
  | { ok: false; failure: SmtpFailure; stage: SmtpStage; code?: number };

/**
 * Why the configuration is unusable, by variable name only (never a value):
 * `missing:MOTION_SMTP_PASSWORD`, `invalid:MOTION_MAIL_FROM`, …
 */
export type SmtpConfigRead =
  | { config: SmtpConfig; issue?: undefined }
  | { config?: undefined; issue: string };

/** Opens the transport. Injected in tests; production uses Deno sockets. */
export type SmtpConnector = (config: SmtpConfig) => Promise<Deno.Conn>;

export type SmtpOptions = {
  connect?: SmtpConnector;
  stepTimeoutMs?: number;
  totalTimeoutMs?: number;
  now?: () => Date;
};

// Plain text is accepted only for a loopback/Docker-host sink in local E2E.
const PLAINTEXT_HOSTS = new Set([
  "127.0.0.1",
  "::1",
  "localhost",
  "host.docker.internal",
]);

const ADDRESS = /^[^\s@<>()",;:\\[\]]{1,64}@[A-Za-z0-9.-]{1,253}$/;

/** The bare address inside a From value, or null when it is not one. */
export function smtpAddress(from: string): string | null {
  const angle = /<([^<>]+)>\s*$/.exec(from);
  const address = (angle ? angle[1] : from).trim();
  return ADDRESS.test(address) ? address : null;
}

/**
 * Google shows an app password as four groups of four letters, and it is
 * often stored with those spaces or a trailing newline; AUTH then fails
 * (CORE-07 6.11, 29 Oct 2026). Surrounding whitespace is always dropped.
 * Inner whitespace is dropped only when what remains has that 16-letter
 * shape, so another provider's password with a space stays as typed.
 */
export function normalizeSmtpPassword(
  value: string | undefined,
): string | undefined {
  if (value === undefined) return undefined;
  const trimmed = value.trim();
  const compact = trimmed.replace(/\s+/g, "");
  return /^[A-Za-z]{16}$/.test(compact) ? compact : trimmed;
}

/**
 * Reads MOTION_SMTP_* and MOTION_MAIL_FROM. Fails closed with an issue
 * (variable name, no value) when anything is missing or unsafe: TLS other
 * than `implicit`, except `none` towards a loopback/Docker host.
 */
export function readSmtpConfig(
  get: (name: string) => string | undefined = (name) => Deno.env.get(name),
): SmtpConfigRead {
  const host = get("MOTION_SMTP_HOST")?.trim();
  const user = get("MOTION_SMTP_USER");
  const password = normalizeSmtpPassword(get("MOTION_SMTP_PASSWORD"));
  const from = get("MOTION_MAIL_FROM")?.trim();
  const tls = (get("MOTION_SMTP_TLS") ?? "implicit").trim();
  const portText = (get("MOTION_SMTP_PORT") ?? "465").trim();
  if (!host) return { issue: "missing:MOTION_SMTP_HOST" };
  if (!user) return { issue: "missing:MOTION_SMTP_USER" };
  if (!password) return { issue: "missing:MOTION_SMTP_PASSWORD" };
  if (!from) return { issue: "missing:MOTION_MAIL_FROM" };
  if (!smtpAddress(from) || /[\r\n]/.test(from)) {
    return { issue: "invalid:MOTION_MAIL_FROM" };
  }
  if (!/^\d{1,5}$/.test(portText)) return { issue: "invalid:MOTION_SMTP_PORT" };
  const port = Number(portText);
  if (port < 1 || port > 65535) return { issue: "invalid:MOTION_SMTP_PORT" };
  if (tls !== "implicit" && tls !== "none") {
    return { issue: "invalid:MOTION_SMTP_TLS" };
  }
  if (tls === "none" && !PLAINTEXT_HOSTS.has(host)) {
    return { issue: "invalid:MOTION_SMTP_TLS" };
  }
  return { config: { host, port, user, password, tls, from } };
}

/** As [readSmtpConfig]; null when the configuration is unusable. */
export function smtpConfigFromEnv(
  get: (name: string) => string | undefined = (name) => Deno.env.get(name),
): SmtpConfig | null {
  return readSmtpConfig(get).config ?? null;
}

const defaultConnector: SmtpConnector = (config) =>
  config.tls === "implicit"
    ? Deno.connectTls({ hostname: config.host, port: config.port })
    : Deno.connect({ hostname: config.host, port: config.port });

const encoder = new TextEncoder();

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

/** RFC 2047 encoded words (UTF-8, base64), split on character boundaries. */
export function encodeHeaderWords(value: string): string {
  if (/^[\x20-\x7e]*$/.test(value) && !/=\?/.test(value)) return value;
  const words: string[] = [];
  let chunk = "";
  for (const char of value) {
    // 39 bytes of UTF-8 encode to 52 base64 characters: with its
    // =?UTF-8?B? ... ?= frame and a "Subject: " prefix a line stays within
    // the recommended 78 characters.
    if (encoder.encode(chunk + char).length > 39) {
      words.push(`=?UTF-8?B?${base64(encoder.encode(chunk))}?=`);
      chunk = "";
    }
    chunk += char;
  }
  if (chunk) words.push(`=?UTF-8?B?${base64(encoder.encode(chunk))}?=`);
  return words.join("\r\n ");
}

function formatFrom(from: string, address: string): string {
  const angle = /^(.*?)\s*<[^<>]+>\s*$/.exec(from);
  const name = angle?.[1].trim().replace(/^"(.*)"$/, "$1") ?? "";
  if (!name) return address;
  const encoded = encodeHeaderWords(name);
  const display = encoded === name && /[()<>@,;:\\".[\]]/.test(name)
    ? `"${name.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`
    : encoded;
  return `${display} <${address}>`;
}

function rfc5322Date(date: Date): string {
  return date.toUTCString().replace("GMT", "+0000");
}

/** The DATA payload: headers, base64 body in 76-column lines, CRLF ends. */
export function buildMessage(
  config: SmtpConfig,
  message: SmtpMessage,
  date: Date,
): string {
  const address = smtpAddress(config.from)!;
  const domain = address.split("@")[1];
  const id = crypto.randomUUID();
  const body = base64(encoder.encode(message.text.replace(/\r?\n/g, "\r\n")))
    .match(/.{1,76}/g) ?? [];
  return [
    `From: ${formatFrom(config.from, address)}`,
    `To: ${message.to}`,
    `Subject: ${encodeHeaderWords(message.subject)}`,
    `Date: ${rfc5322Date(date)}`,
    `Message-ID: <${id}@${domain}>`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    ...body,
  ].join("\r\n");
}

class SmtpReplyError extends Error {}

/** The server answered with a code the step does not accept. */
class SmtpRefused extends Error {
  constructor(readonly code: number) {
    super("refused");
  }
}

const REFUSAL: Record<SmtpStage, SmtpFailure> = {
  config: "config",
  connect: "network",
  greeting: "network",
  ehlo: "network",
  auth: "auth",
  mail_from: "sender",
  rcpt: "recipient",
  data: "message",
  message: "message",
};

/** Line reader over one connection; replies may span "250-…" lines. */
class Replies {
  #buffer = "";
  #decoder = new TextDecoder();
  #chunk = new Uint8Array(4096);

  constructor(private readonly conn: Deno.Conn) {}

  async next(): Promise<number> {
    for (;;) {
      const end = this.#buffer.indexOf("\r\n");
      if (end >= 0) {
        const line = this.#buffer.slice(0, end);
        this.#buffer = this.#buffer.slice(end + 2);
        const match = /^(\d{3})([ -])/.exec(line) ?? /^(\d{3})$/.exec(line);
        if (!match) throw new SmtpReplyError("malformed reply");
        if (match[2] === "-") continue;
        return Number(match[1]);
      }
      if (this.#buffer.length > 64 * 1024) {
        throw new SmtpReplyError("reply too long");
      }
      const read = await this.conn.read(this.#chunk);
      if (read === null) throw new SmtpReplyError("connection closed");
      this.#buffer += this.#decoder.decode(this.#chunk.subarray(0, read), {
        stream: true,
      });
    }
  }
}

async function writeAll(conn: Deno.Conn, text: string): Promise<void> {
  const bytes = encoder.encode(text);
  let written = 0;
  while (written < bytes.length) {
    written += await conn.write(bytes.subarray(written));
  }
}

/**
 * Sends one message. Resolves true only after the server accepted the DATA
 * (250); any refusal, timeout, transport error or malformed reply resolves
 * false. Never throws and never logs.
 */
export async function sendSmtpMail(
  config: SmtpConfig,
  message: SmtpMessage,
  options: SmtpOptions = {},
): Promise<boolean> {
  return (await submitSmtpMail(config, message, options)).ok;
}

/**
 * As [sendSmtpMail], with a secret-free outcome: a refusal carries the class
 * of the refusing step and its reply code; a timeout, transport error or
 * malformed reply is `network` at the stage it happened. Never throws and
 * never logs.
 */
export async function submitSmtpMail(
  config: SmtpConfig,
  message: SmtpMessage,
  options: SmtpOptions = {},
): Promise<SmtpOutcome> {
  const from = smtpAddress(config.from);
  if (
    !from || !ADDRESS.test(message.to) || /[\r\n]/.test(message.subject)
  ) return { ok: false, failure: "message", stage: "message" };
  let stage: SmtpStage = "connect";
  const stepMs = options.stepTimeoutMs ?? 10_000;
  const totalMs = options.totalTimeoutMs ?? 30_000;
  let conn: Deno.Conn | undefined;
  let totalTimer: ReturnType<typeof setTimeout> | undefined;
  let stepTimer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<never>((_, reject) => {
    totalTimer = setTimeout(
      () => reject(new SmtpReplyError("deadline")),
      totalMs,
    );
  });
  expired.catch(() => {});
  const step = <T>(work: Promise<T>): Promise<T> => {
    clearTimeout(stepTimer);
    const timeout = new Promise<never>((_, reject) => {
      stepTimer = setTimeout(
        () => reject(new SmtpReplyError("step timeout")),
        stepMs,
      );
    });
    timeout.catch(() => {});
    return Promise.race([work, timeout, expired]);
  };
  try {
    conn = await step((options.connect ?? defaultConnector)(config));
    const replies = new Replies(conn);
    const expect = async (
      at: SmtpStage,
      command: string | null,
      ...codes: number[]
    ) => {
      stage = at;
      if (command !== null) await step(writeAll(conn!, command + "\r\n"));
      const code = await step(replies.next());
      if (!codes.includes(code)) throw new SmtpRefused(code);
    };
    await expect("greeting", null, 220);
    await expect("ehlo", "EHLO motion.yulalab.com", 250);
    const credentials = base64(
      encoder.encode(`\0${config.user}\0${config.password}`),
    );
    await expect("auth", `AUTH PLAIN ${credentials}`, 235);
    await expect("mail_from", `MAIL FROM:<${from}>`, 250);
    await expect("rcpt", `RCPT TO:<${message.to}>`, 250, 251);
    await expect("data", "DATA", 354);
    const payload = buildMessage(
      config,
      message,
      (options.now ?? (() => new Date()))(),
    )
      .split("\r\n")
      .map((line) => (line.startsWith(".") ? "." + line : line))
      .join("\r\n");
    await expect("data", payload + "\r\n.", 250);
    // The message is accepted; a failed QUIT does not undo delivery.
    try {
      await step(writeAll(conn, "QUIT\r\n"));
      await step(replies.next());
    } catch {
      // ignore
    }
    return { ok: true };
  } catch (error) {
    return error instanceof SmtpRefused
      ? { ok: false, failure: REFUSAL[stage], stage, code: error.code }
      : { ok: false, failure: "network", stage };
  } finally {
    clearTimeout(stepTimer);
    clearTimeout(totalTimer);
    try {
      conn?.close();
    } catch {
      // already closed
    }
  }
}
