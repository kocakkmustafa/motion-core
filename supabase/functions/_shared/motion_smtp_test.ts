// CORE-05: Google Workspace SMTP (465, implicit TLS) for parental consent mail.
// A loopback fake server stands in for smtp.gmail.com through the injected
// connector; the TLS choice itself is checked on the connector call.
import { FakeSmtp } from "../tests/fake_smtp.ts";
import {
  encodeHeaderWords,
  normalizeSmtpPassword,
  readSmtpConfig,
  sendSmtpMail,
  type SmtpConfig,
  smtpConfigFromEnv,
  submitSmtpMail,
} from "./motion_smtp.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

const config: SmtpConfig = {
  host: "smtp.gmail.com",
  port: 465,
  user: "consent@example.invalid",
  password: "fixture-app-password",
  tls: "implicit",
  from: "Motion Ebeveyn Onayı <consent@example.invalid>",
};

function loopback(server: FakeSmtp, seen: SmtpConfig[] = []) {
  return (target: SmtpConfig) => {
    seen.push(target);
    return Deno.connect({ hostname: "127.0.0.1", port: server.port });
  };
}

async function quietly<T>(work: () => Promise<T>) {
  const logged: unknown[] = [];
  const original = { ...console };
  for (const name of ["log", "info", "warn", "error", "debug"] as const) {
    console[name] = (...args: unknown[]) => logged.push(args);
  }
  try {
    return { result: await work(), logged };
  } finally {
    Object.assign(console, original);
  }
}

Deno.test("a message is submitted with AUTH PLAIN and UTF-8 headers", async () => {
  const server = new FakeSmtp();
  const seen: SmtpConfig[] = [];
  try {
    const subject = "Motion: çocuğunun hesabı için onay gerekiyor — İstanbul";
    const text = "Merhaba,\n.ilk satır noktayla başlıyor\nŞimdi onayla: ğüşıöç";
    const { result, logged } = await quietly(() =>
      sendSmtpMail(config, { to: "parent@example.invalid", subject, text }, {
        connect: loopback(server, seen),
        now: () => new Date("2026-10-25T09:00:00Z"),
      })
    );
    assert(result === true, "accepted");
    assert(seen.length === 1 && seen[0].tls === "implicit", "implicit TLS");
    assert(logged.length === 0, "nothing logged");
    assert(
      JSON.stringify(server.commands) === JSON.stringify([
        "EHLO motion.yulalab.com",
        "AUTH PLAIN ***",
        "MAIL FROM:<consent@example.invalid>",
        "RCPT TO:<parent@example.invalid>",
        "DATA",
        "QUIT",
      ]),
      `command order ${server.commands}`,
    );
    const mail = server.mails[0];
    assert(
      mail.auth === "\0consent@example.invalid\0fixture-app-password",
      "AUTH PLAIN credentials",
    );
    assert(mail.subject === subject, "subject round trip");
    assert(mail.text === text.replaceAll("\n", "\r\n"), "body round trip");
    assert(mail.headers["to"] === "parent@example.invalid", "To");
    assert(
      mail.headers["from"].endsWith("<consent@example.invalid>") &&
        mail.headers["from"].startsWith("=?UTF-8?B?"),
      "encoded From name",
    );
    assert(mail.headers["date"] === "Sun, 25 Oct 2026 09:00:00 +0000", "Date");
    assert(
      /^<[0-9a-f-]{36}@example\.invalid>$/.test(mail.headers["message-id"]),
      "Message-ID",
    );
    assert(
      mail.headers["content-type"] === "text/plain; charset=UTF-8",
      "type",
    );
    assert(mail.headers["content-transfer-encoding"] === "base64", "cte");
    for (const line of mail.raw.split("\r\n")) {
      assert(
        new TextEncoder().encode(line).length <= 78,
        `line length ${line}`,
      );
    }
    assert(!mail.raw.includes("fixture-app-password"), "no password in mail");
  } finally {
    await server.close();
  }
});

Deno.test("a refused login sends nothing and reports false", async () => {
  const server = new FakeSmtp({ authReply: "535 5.7.8 bad credentials" });
  try {
    const { result, logged } = await quietly(() =>
      sendSmtpMail(config, {
        to: "parent@example.invalid",
        subject: "s",
        text: "t",
      }, { connect: loopback(server) })
    );
    assert(result === false, "refused");
    assert(logged.length === 0, "nothing logged");
    assert(
      !server.commands.some((command) => command.startsWith("MAIL")),
      "no MAIL FROM after refused AUTH",
    );
    assert(server.mails.length === 0, "no message");
  } finally {
    await server.close();
  }
});

Deno.test("a silent server times out within the step deadline", async () => {
  const server = new FakeSmtp({ silent: true });
  try {
    const started = performance.now();
    const result = await sendSmtpMail(config, {
      to: "parent@example.invalid",
      subject: "s",
      text: "t",
    }, { connect: loopback(server), stepTimeoutMs: 200, totalTimeoutMs: 2000 });
    assert(result === false, "timeout is false");
    assert(performance.now() - started < 1500, "step deadline");
  } finally {
    await server.close();
  }
});

Deno.test("a connect failure and header injection both report false", async () => {
  const refused = await sendSmtpMail(config, {
    to: "parent@example.invalid",
    subject: "s",
    text: "t",
  }, { connect: () => Promise.reject(new Error("private host detail")) });
  assert(refused === false, "connect failure");
  const injected = await sendSmtpMail(config, {
    to: "parent@example.invalid",
    subject: "s\r\nBcc: x@example.invalid",
    text: "t",
  }, { connect: () => Promise.reject(new Error("not reached")) });
  assert(injected === false, "CRLF subject");
  const badTo = await sendSmtpMail(config, {
    to: "a@example.invalid>\r\nRCPT TO:<b@example.invalid",
    subject: "s",
    text: "t",
  }, { connect: () => Promise.reject(new Error("not reached")) });
  assert(badTo === false, "bad recipient");
});

Deno.test("configuration requires implicit TLS except for a loopback sink", () => {
  const env = (values: Record<string, string>) => (name: string) =>
    values[name];
  const base = {
    MOTION_SMTP_HOST: "smtp.gmail.com",
    MOTION_SMTP_USER: "consent@example.invalid",
    MOTION_SMTP_PASSWORD: "fixture",
    MOTION_MAIL_FROM: "Motion <consent@example.invalid>",
  };
  const production = smtpConfigFromEnv(env(base));
  assert(
    production?.tls === "implicit" && production.port === 465,
    "defaults: 465 implicit",
  );
  assert(
    smtpConfigFromEnv(env({ ...base, MOTION_SMTP_TLS: "none" })) === null,
    "plaintext refused for a remote host",
  );
  assert(
    smtpConfigFromEnv(env({ ...base, MOTION_SMTP_TLS: "starttls" })) === null,
    "unknown TLS mode refused",
  );
  for (const host of ["127.0.0.1", "host.docker.internal"]) {
    const local = smtpConfigFromEnv(
      env({
        ...base,
        MOTION_SMTP_HOST: host,
        MOTION_SMTP_PORT: "2525",
        MOTION_SMTP_TLS: "none",
      }),
    );
    assert(local?.tls === "none" && local.port === 2525, `${host} sink`);
  }
  for (const missing of Object.keys(base)) {
    const partial: Record<string, string> = { ...base };
    delete partial[missing];
    assert(smtpConfigFromEnv(env(partial)) === null, `missing ${missing}`);
  }
  assert(
    smtpConfigFromEnv(env({ ...base, MOTION_SMTP_PORT: "70000" })) === null,
    "port range",
  );
  assert(
    smtpConfigFromEnv(env({ ...base, MOTION_MAIL_FROM: "not an address" })) ===
      null,
    "From address",
  );
});

Deno.test("encoded words stay within 75 characters and keep characters whole", () => {
  const subject = "ğüşıöçĞÜŞİÖÇ ".repeat(8);
  const encoded = encodeHeaderWords(subject);
  for (const word of encoded.split("\r\n ")) {
    assert(word.length <= 75, `word length ${word.length}`);
  }
  const decoded = encoded.split("\r\n ").map((word) => {
    const b64 = /^=\?UTF-8\?B\?(.*)\?=$/.exec(word)![1];
    return new TextDecoder("utf-8", { fatal: true }).decode(
      Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)),
    );
  }).join("");
  assert(decoded === subject, "round trip");
  assert(encodeHeaderWords("Plain ASCII") === "Plain ASCII", "ASCII as is");
});

Deno.test("a Google app password loses its display spaces, others are only trimmed", () => {
  const cases: [string | undefined, string | undefined][] = [
    ["abcd efgh ijkl mnop", "abcdefghijklmnop"],
    [" abcd efgh ijkl mnop\n", "abcdefghijklmnop"],
    ["abcd\u00a0efgh\u00a0ijkl\u00a0mnop", "abcdefghijklmnop"],
    ["abcdefghijklmnop\r\n", "abcdefghijklmnop"],
    ["correct horse battery", "correct horse battery"],
    ["  pass word 1 \n", "pass word 1"],
    ["abcd efgh ijkl mno1", "abcd efgh ijkl mno1"],
    ["   ", ""],
    [undefined, undefined],
  ];
  for (const [raw, expected] of cases) {
    assert(
      normalizeSmtpPassword(raw) === expected,
      `${JSON.stringify(raw)} -> ${JSON.stringify(normalizeSmtpPassword(raw))}`,
    );
  }
  const env = (values: Record<string, string>) => (name: string) =>
    values[name];
  const base = {
    MOTION_SMTP_HOST: "smtp.gmail.com",
    MOTION_SMTP_USER: "consent@example.invalid",
    MOTION_MAIL_FROM: "Motion <consent@example.invalid>",
  };
  assert(
    smtpConfigFromEnv(
      env({ ...base, MOTION_SMTP_PASSWORD: "abcd efgh ijkl mnop" }),
    )
      ?.password === "abcdefghijklmnop",
    "config carries the compact password",
  );
  assert(
    readSmtpConfig(env({ ...base, MOTION_SMTP_PASSWORD: " \n" })).issue ===
      "missing:MOTION_SMTP_PASSWORD",
    "whitespace-only password is missing",
  );
});

Deno.test("configuration issues name the variable, never its value", () => {
  const env = (values: Record<string, string>) => (name: string) =>
    values[name];
  const base: Record<string, string> = {
    MOTION_SMTP_HOST: "smtp.gmail.com",
    MOTION_SMTP_USER: "consent@example.invalid",
    MOTION_SMTP_PASSWORD: "fixture-secret",
    MOTION_MAIL_FROM: "Motion <consent@example.invalid>",
  };
  const cases: [Record<string, string>, string][] = [
    [{ ...base, MOTION_SMTP_HOST: "" }, "missing:MOTION_SMTP_HOST"],
    [{ ...base, MOTION_SMTP_USER: "" }, "missing:MOTION_SMTP_USER"],
    [{ ...base, MOTION_MAIL_FROM: "" }, "missing:MOTION_MAIL_FROM"],
    [
      { ...base, MOTION_MAIL_FROM: "fixture-secret" },
      "invalid:MOTION_MAIL_FROM",
    ],
    [{ ...base, MOTION_SMTP_PORT: "x" }, "invalid:MOTION_SMTP_PORT"],
    [{ ...base, MOTION_SMTP_PORT: "0" }, "invalid:MOTION_SMTP_PORT"],
    [{ ...base, MOTION_SMTP_TLS: "starttls" }, "invalid:MOTION_SMTP_TLS"],
    [{ ...base, MOTION_SMTP_TLS: "none" }, "invalid:MOTION_SMTP_TLS"],
  ];
  for (const [values, issue] of cases) {
    const read = readSmtpConfig(env(values));
    assert(
      read.config === undefined && read.issue === issue,
      `${issue}: ${read.issue}`,
    );
  }
  assert(readSmtpConfig(env(base)).config !== undefined, "complete config");
});

Deno.test("the outcome names the refusing step and its reply code only", async () => {
  const message = { to: "parent@example.invalid", subject: "s", text: "t" };
  const auth = new FakeSmtp({ authReply: "535 5.7.8 bad credentials" });
  const rcpt = new FakeSmtp({ rcptReply: "550 5.1.1 no such user" });
  const silent = new FakeSmtp({ silent: true });
  const ok = new FakeSmtp();
  try {
    const outcomes = [
      await submitSmtpMail(config, message, { connect: loopback(auth) }),
      await submitSmtpMail(config, message, { connect: loopback(rcpt) }),
      await submitSmtpMail(config, message, {
        connect: loopback(silent),
        stepTimeoutMs: 100,
        totalTimeoutMs: 1000,
      }),
      await submitSmtpMail(config, message, {
        connect: () => Promise.reject(new Error("private host detail")),
      }),
      await submitSmtpMail(config, { ...message, subject: "a\r\nBcc: x" }),
      await submitSmtpMail(config, message, { connect: loopback(ok) }),
    ];
    assert(
      JSON.stringify(outcomes) === JSON.stringify([
        { ok: false, failure: "auth", stage: "auth", code: 535 },
        { ok: false, failure: "recipient", stage: "rcpt", code: 550 },
        { ok: false, failure: "network", stage: "greeting" },
        { ok: false, failure: "network", stage: "connect" },
        { ok: false, failure: "message", stage: "message" },
        { ok: true },
      ]),
      JSON.stringify(outcomes),
    );
  } finally {
    await Promise.all([auth.close(), rcpt.close(), silent.close(), ok.close()]);
  }
});
