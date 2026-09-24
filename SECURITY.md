# Security Policy

## Supported versions

Only the latest `main` is supported. There are no separate release branches.

## Reporting a vulnerability

**Please do not open a public issue.** Contact the maintainer privately via the contact details on
[github.com/ibroxiim](https://github.com/ibroxiim) and include:

- what the issue is and where (file, feature),
- steps to reproduce,
- what an attacker could do with it.

You will get a reply within 7 days. Once a fix is in `main`, you are welcome to be credited.

Things that are especially relevant for this project:

- a committed API key or other secret (keys belong in the gitignored `Shared/Secrets.swift`),
- ways the keyboard could leak typed text, or the app could leak DM screenshots or chat context,
- anything that lets a third party read the shared App Group data.

---

## Xavfsizlik (o'zbekcha)

Faqat oxirgi `main` qo'llab-quvvatlanadi. Xavfsizlik zaifligini topsangiz, **ochiq issue ochmang** —
[github.com/ibroxiim](https://github.com/ibroxiim) profilidagi aloqa orqali maxfiy yozing: nima, qayerda,
qanday takrorlanadi va qanday zarar yetkazishi mumkin. 7 kun ichida javob beriladi.
