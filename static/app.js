"use strict";

const CHAT_STORAGE_KEY = "local-ai.conversations.v1";
const CURRENT_CHAT_KEY = "local-ai.current-chat.v1";
const MAX_LOCAL_CONVERSATIONS = 100;
const MAX_MESSAGES_PER_REQUEST = 40;
const MAX_MESSAGE_LENGTH = 12000;
const MAX_HISTORY_LENGTH = 40000;
const suggestions = [
  ["Explain a concept", "Break a complex idea into simple steps"],
  ["Write some code", "Help me solve a programming problem"],
  ["Think it through", "Explore an idea from a new angle"],
  ["Plan something", "Turn a goal into a clear next step"],
];

const shell = document.querySelector("#appShell");
const onboardingView = document.querySelector("#onboardingView");
const authView = document.querySelector("#authView");
const historyList = document.querySelector("#historyList");
const messagesEl = document.querySelector("#messages");
const conversationEl = document.querySelector("#conversation");
const conversationTitle = document.querySelector("#conversationTitle");
const messageInput = document.querySelector("#messageInput");
const composerForm = document.querySelector("#composerForm");
const sendButton = document.querySelector("#sendButton");
const stopButton = document.querySelector("#stopButton");
const topbarStopButton = document.querySelector("#topbarStopButton");
const toastEl = document.querySelector("#toast");
const searchInput = document.querySelector("#searchInput");
const settingsDialog = document.querySelector("#settingsDialog");
const messageNodes = new Map();

let authenticatedUser = null;
let conversations = [];
let currentConversation = makeConversation();
let activeGeneration = null;
let onboardingStep = 0;
let healthInterval = 0;
let toastTimeout = 0;
let saveTimeout = 0;

function getApiBaseUrl() {
  if (typeof window.LUMA_API_BASE_URL === "string" && window.LUMA_API_BASE_URL.trim()) {
    return window.LUMA_API_BASE_URL.trim().replace(/\/+$/, "");
  }
  const meta = document.querySelector('meta[name="api-base-url"]');
  if (meta && typeof meta.content === "string" && meta.content.trim()) {
    return meta.content.trim().replace(/\/+$/, "");
  }
  try {
    const stored = localStorage.getItem("luma.api_base_url");
    if (stored && stored.trim()) return stored.trim().replace(/\/+$/, "");
  } catch {}
  if (
    (location.hostname === "127.0.0.1" || location.hostname === "localhost") &&
    location.port &&
    location.port !== "8000"
  ) {
    return `${location.protocol}//${location.hostname}:8000`;
  }
  return "";
}

function apiUrl(endpoint) {
  const base = getApiBaseUrl();
  const cleanEndpoint = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;
  return base ? `${base}${cleanEndpoint}` : cleanEndpoint;
}

async function apiFetch(endpoint, options = {}) {
  const isCrossOrigin = Boolean(getApiBaseUrl());
  return fetch(apiUrl(endpoint), {
    credentials: options.credentials || (isCrossOrigin ? "include" : "same-origin"),
    ...options,
    headers: {
      ...options.headers,
    },
  });
}

function accountStorageKey(key) {
  return authenticatedUser?.id ? `${key}.${authenticatedUser.id}` : null;
}

function readStorage(key) {
  if (!key) return null;
  try {
    return window.localStorage.getItem(key);
  } catch {
    showToast("Browser storage is unavailable. Your conversations may not be saved.");
    return null;
  }
}

function loadConversations() {
  const raw = readStorage(accountStorageKey(CHAT_STORAGE_KEY));
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new TypeError("Conversation list is not an array.");
    return parsed
      .filter((item) => item && typeof item.id === "string" && Array.isArray(item.messages))
      .map((item) => ({
        id: item.id,
        title: typeof item.title === "string" ? item.title.slice(0, 80) : "New conversation",
        createdAt: Number.isFinite(item.createdAt) ? item.createdAt : Date.now(),
        updatedAt: Number.isFinite(item.updatedAt) ? item.updatedAt : Date.now(),
        messages: item.messages
          .filter((message) =>
            message &&
            (message.role === "user" || message.role === "assistant") &&
            typeof message.content === "string"
          )
          .map((message) => ({
            id: typeof message.id === "string" ? message.id : makeId(),
            role: message.role,
            content: message.content.slice(0, MAX_MESSAGE_LENGTH),
            createdAt: Number.isFinite(message.createdAt)
              ? message.createdAt
              : Number.isFinite(item.updatedAt) ? item.updatedAt : Date.now(),
            status: message.status === "failed"
              ? "failed"
              : message.status === "streaming"
                ? "failed"
                : "complete",
            error: message.status === "streaming"
              ? "This response was interrupted when the page closed."
              : typeof message.error === "string" && /ollama/i.test(message.error)
                ? "Luma AI is temporarily unavailable. Please try again."
              : typeof message.error === "string" ? message.error : "",
          })),
      }))
      .filter((conversation) => conversation.messages.length > 0)
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .slice(0, MAX_LOCAL_CONVERSATIONS);
  } catch {
    window.setTimeout(() => showToast("Saved conversation data could not be read. Starting with an empty history."), 0);
    return [];
  }
}

function findConversation(id) {
  return typeof id === "string" ? conversations.find((item) => item.id === id) ?? null : null;
}

function makeId() {
  return globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function makeConversation() {
  const now = Date.now();
  return { id: makeId(), title: "New conversation", createdAt: now, updatedAt: now, messages: [] };
}

function persist() {
  if (!authenticatedUser) return false;
  window.clearTimeout(saveTimeout);
  try {
    conversations = conversations
      .filter((conversation) => conversation.messages.length > 0)
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .slice(0, MAX_LOCAL_CONVERSATIONS);
    window.localStorage.setItem(accountStorageKey(CHAT_STORAGE_KEY), JSON.stringify(conversations));
    window.localStorage.setItem(accountStorageKey(CURRENT_CHAT_KEY), currentConversation.id);
    renderHistory();
    return true;
  } catch {
    showToast("Could not save conversations in this browser. Check available storage.");
    return false;
  }
}

function persistSoon() {
  window.clearTimeout(saveTimeout);
  saveTimeout = window.setTimeout(persist, 250);
}

function showToast(message) {
  toastEl.textContent = message;
  toastEl.classList.add("visible");
  window.clearTimeout(toastTimeout);
  toastTimeout = window.setTimeout(() => toastEl.classList.remove("visible"), 3200);
}

function currentChat() {
  return conversations.find((conversation) => conversation.id === currentConversation.id) ?? currentConversation;
}

function keepScrolledToBottom() {
  const distance = conversationEl.scrollHeight - conversationEl.scrollTop - conversationEl.clientHeight;
  if (distance < 180) {
    conversationEl.scrollTop = conversationEl.scrollHeight;
  }
}

function renderHistory() {
  const query = searchInput.value.trim().toLocaleLowerCase();
  const matching = conversations
    .filter((conversation) => conversation.title.toLocaleLowerCase().includes(query))
    .sort((a, b) => b.updatedAt - a.updatedAt);
  historyList.replaceChildren();

  if (matching.length === 0) {
    const empty = document.createElement("p");
    empty.className = "empty-history";
    empty.textContent = query ? "No matching conversations." : "Your conversations will appear here.";
    historyList.append(empty);
    return;
  }

  const groups = new Map();
  for (const conversation of matching) {
    const group = historyGroup(conversation.updatedAt);
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(conversation);
  }

  for (const [group, chats] of groups) {
    const section = document.createElement("section");
    section.className = "history-group";
    const label = document.createElement("h2");
    label.className = "history-label";
    label.textContent = group;
    section.append(label);
    for (const chat of chats) section.append(createHistoryItem(chat));
    historyList.append(section);
  }
}

function historyGroup(timestamp) {
  const age = Math.max(0, Date.now() - timestamp);
  if (age < 86_400_000) return "Today";
  if (age < 7 * 86_400_000) return "Previous 7 days";
  return "Earlier";
}

function createHistoryItem(chat) {
  const item = document.createElement("div");
  item.className = `history-item${chat.id === currentConversation.id ? " active" : ""}`;
  item.dataset.chatId = chat.id;

  const icon = document.createElement("span");
  icon.className = "history-icon";
  icon.append(makeSvg('<path d="M5 4.5h9l5 5V19a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19V4.5Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M14 4.8v5h4.5M8 13h8M8 16.5h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'));
  item.append(icon);

  const details = document.createElement("span");
  details.className = "history-details";
  const title = document.createElement("span");
  title.className = "history-title";
  title.textContent = chat.title;
  const updated = document.createElement("span");
  updated.className = "history-time";
  updated.textContent = formatHistoryTime(chat.updatedAt);
  details.append(title, updated);
  item.append(details);

  const actions = document.createElement("span");
  actions.className = "history-actions";
  actions.append(
    createHistoryAction("Rename conversation", "rename", iconPencil()),
    createHistoryAction("Delete conversation", "delete", iconTrash(), "delete"),
  );
  item.append(actions);
  return item;
}

function formatHistoryTime(timestamp) {
  const date = new Date(timestamp);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const daysAgo = Math.round((startOfToday - startOfDate) / 86_400_000);
  const time = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(date);
  if (daysAgo === 0) return `Today, ${time}`;
  if (daysAgo === 1) return `Yesterday, ${time}`;
  if (daysAgo < 7) {
    return `${new Intl.DateTimeFormat(undefined, { weekday: "short" }).format(date)}, ${time}`;
  }
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(date);
}

function formatMessageTime(timestamp) {
  return new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(timestamp);
}

function createHistoryAction(label, action, icon, extraClass = "") {
  const button = document.createElement("button");
  button.className = `history-action ${extraClass}`.trim();
  button.type = "button";
  button.dataset.action = action;
  button.setAttribute("aria-label", label);
  button.title = label;
  button.append(icon);
  return button;
}

function iconPencil() {
  return makeSvg('<path d="m14.5 5.5 4 4M4 20l4.1-.9L19 8.2a2.1 2.1 0 0 0-3-3L5.1 16.1 4 20Z" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>');
}

function iconTrash() {
  return makeSvg('<path d="M4.5 7h15M10 11v5m4-5v5M6.5 7l.8 12h9.4l.8-12M9 7V4.5h6V7" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>');
}

function iconCopy() {
  return makeSvg('<rect x="8" y="8" width="11" height="12" rx="2" stroke="currentColor" stroke-width="1.6"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h2" stroke="currentColor" stroke-width="1.6"/>');
}

function makeSvg(pathMarkup) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("aria-hidden", "true");
  const template = document.createElementNS("http://www.w3.org/2000/svg", "g");
  template.innerHTML = pathMarkup;
  svg.append(...template.childNodes);
  return svg;
}

function renderConversation({ scroll = false } = {}) {
  const chat = currentChat();
  messageNodes.clear();
  messagesEl.replaceChildren();
  conversationTitle.textContent = chat.messages.length ? chat.title : "New conversation";

  if (chat.messages.length === 0) {
    messagesEl.append(createWelcome());
  } else {
    for (const message of chat.messages) {
      messagesEl.append(createMessage(message, chat.id));
    }
  }
  renderHistory();
  updateGenerationControls();
  if (scroll) requestAnimationFrame(keepScrolledToBottom);
}

function createWelcome() {
  const welcome = document.createElement("div");
  welcome.className = "welcome";
  const mark = document.createElement("div");
  mark.className = "welcome-mark";
  const spark = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  spark.setAttribute("viewBox", "0 0 24 24");
  spark.setAttribute("fill", "none");
  spark.setAttribute("aria-hidden", "true");
  const shape = document.createElementNS("http://www.w3.org/2000/svg", "path");
  shape.setAttribute("d", "M12 3.5 14.4 9.6 20.5 12l-6.1 2.4L12 20.5l-2.4-6.1L3.5 12l6.1-2.4L12 3.5Z");
  shape.setAttribute("stroke", "currentColor");
  shape.setAttribute("stroke-width", "1.5");
  shape.setAttribute("stroke-linejoin", "round");
  spark.append(shape);
  mark.append(spark);
  const heading = document.createElement("h1");
  heading.textContent = "A thoughtful space to think.";
  const subtitle = document.createElement("p");
  subtitle.textContent = "Ask a question, explore an idea, or make a plan. Your conversation stays right here on your device.";
  const grid = document.createElement("div");
  grid.className = "suggestions";
  for (const [title, detail] of suggestions) {
    const button = document.createElement("button");
    button.className = "suggestion";
    button.type = "button";
    const strong = document.createElement("strong");
    strong.textContent = title;
    const span = document.createElement("span");
    span.textContent = detail;
    button.append(strong, span);
    button.addEventListener("click", () => {
      const prompts = {
        "Explain a concept": "What is a concept you would like explained?",
        "Write some code": "What programming problem can I help you solve?",
        "Think it through": "What idea would you like to explore?",
        "Plan something": "What goal would you like help planning?",
      };
      messageInput.value = prompts[title];
      resizeInput();
      composerForm.requestSubmit();
    });
    grid.append(button);
  }
  welcome.append(mark, heading, subtitle, grid);
  return welcome;
}

function createMessage(message, conversationId) {
  const card = document.createElement("article");
  card.className = `message ${message.role}`;
  card.dataset.messageId = message.id;

  const avatar = document.createElement("span");
  avatar.className = "message-avatar";
  avatar.setAttribute("aria-hidden", "true");
  avatar.textContent = message.role === "user" ? "Y" : "✳";
  const main = document.createElement("div");
  main.className = "message-main";
  const heading = document.createElement("div");
  heading.className = "message-heading";
  const name = document.createElement("strong");
  name.textContent = message.role === "user" ? "You" : "Luma AI";
  heading.append(name);
  const time = document.createElement("time");
  time.className = "message-time";
  time.dateTime = new Date(message.createdAt ?? Date.now()).toISOString();
  time.textContent = formatMessageTime(message.createdAt ?? Date.now());
  heading.append(time);
  if (message.role === "user") {
    const delivered = document.createElement("span");
    delivered.className = "message-delivered";
    delivered.setAttribute("aria-label", "Sent");
    delivered.textContent = "✓✓";
    heading.append(delivered);
  }
  const body = document.createElement("div");
  body.className = "message-body";
  body.dataset.messageBody = "";
  body.textContent = message.content;
  main.append(heading, body);

  const entry = { card, body, conversationId };
  messageNodes.set(message.id, entry);
  if (message.role === "assistant") {
    const actions = document.createElement("div");
    actions.className = "message-actions";
    const copy = document.createElement("button");
    copy.className = "message-action copy-message";
    copy.type = "button";
    copy.dataset.messageId = message.id;
    copy.append(iconCopy(), document.createTextNode("Copy"));
    actions.append(copy);
    main.append(actions);
    entry.actions = actions;
    entry.error = null;
    if (message.status === "streaming") {
      body.classList.add("streaming-text");
      if (!message.content) body.append(createThinkingIndicator());
    } else if (message.status === "complete" && message.content) {
      requestMarkdown(message.id, conversationId, message.content);
    }
    if (message.status === "failed") showMessageError(entry, message);
  }

  if (message.role === "user") card.append(main, avatar);
  else card.append(avatar, main);
  if (message.status === "streaming" && !message.content) body.replaceChildren(createThinkingIndicator());
  return card;
}

function createThinkingIndicator() {
  const indicator = document.createElement("span");
  indicator.className = "thinking";
  indicator.setAttribute("aria-label", "Luma AI is thinking");
  indicator.append(document.createElement("span"), document.createElement("span"), document.createElement("span"));
  return indicator;
}

function updateAssistantMessage(chat, message) {
  if (chat.id !== currentConversation.id) return;
  const entry = messageNodes.get(message.id);
  if (!entry) return;
  entry.body.classList.add("streaming-text");
  entry.body.textContent = message.content;
  if (!message.content) entry.body.append(createThinkingIndicator());
  keepScrolledToBottom();
}

function showMessageError(entry, message) {
  entry.body.classList.remove("streaming-text");
  entry.body.textContent = message.content;
  if (entry.error) entry.error.remove();
  const error = document.createElement("div");
  error.className = "message-error";
  const text = document.createElement("span");
  text.textContent = message.error || "The response was interrupted.";
  const retry = document.createElement("button");
  retry.className = "retry-button";
  retry.type = "button";
  retry.dataset.retryMessageId = message.id;
  retry.textContent = "Retry";
  error.append(text, retry);
  entry.actions.after(error);
  entry.error = error;
}

async function requestMarkdown(messageId, conversationId, content) {
  if (!authenticatedUser) return;
  try {
    const response = await apiFetch("/api/markdown", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content }),
    });
    if (response.status === 401) {
      if (authenticatedUser) handleSessionExpired();
      return;
    }
    if (!response.ok) return;
    const payload = await response.json();
    const entry = messageNodes.get(messageId);
    if (!entry || entry.conversationId !== conversationId || entry.body.classList.contains("streaming-text")) return;
    entry.body.innerHTML = payload.html;
    const chat = conversations.find((item) => item.id === conversationId);
    const assistantIndex = chat?.messages.findIndex((message) => message.id === messageId) ?? -1;
    const latestUserPrompt = assistantIndex < 0
      ? ""
      : chat.messages.slice(0, assistantIndex).reverse().find((message) => message.role === "user")?.content ?? "";
    enhanceCodeBlocks(entry.body, {
      downloadable: requestsDownloadableCode(latestUserPrompt),
      prompt: latestUserPrompt,
    });
  } catch {
    // Keep the already rendered response as text if Markdown rendering is unavailable.
  }
}

function requestsDownloadableCode(prompt) {
  const asksForFile = /\b(?:download(?:able)?|ready[\s-]+to[\s-]+download|project\s+files?|complete\s+files?|save\s+(?:it|this|the\s+code)|source\s+file|(?:create|generate|make|write|provide|give).{0,60}\bfile\b)\b/i.test(prompt);
  const asksForCode = /\b(?:code|source|program|script|project|file|python|html|css|javascript|typescript|json|markdown|sql)\b/i.test(prompt);
  return asksForFile && asksForCode;
}

function enhanceCodeBlocks(body, { downloadable = false, prompt = "" } = {}) {
  for (const pre of body.querySelectorAll("pre")) {
    if (pre.querySelector(".code-toolbar")) continue;
    const code = pre.querySelector("code");
    const languageMatch = code?.className.match(/(?:^|\s)language-([A-Za-z0-9_+.-]+)/);
    const toolbar = document.createElement("div");
    toolbar.className = "code-toolbar";
    const language = document.createElement("span");
    language.textContent = languageMatch?.[1] ?? "Code";
    const actions = document.createElement("span");
    actions.className = "code-actions";
    const copy = document.createElement("button");
    copy.className = "code-copy";
    copy.type = "button";
    copy.textContent = "Copy";
    copy.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(code?.textContent ?? "");
        copy.textContent = "Copied";
        window.setTimeout(() => { copy.textContent = "Copy"; }, 1400);
      } catch {
        showToast("Clipboard access is unavailable in this browser.");
      }
    });
    actions.append(copy);
    if (downloadable && isDownloadableCodeBlock(pre, languageMatch?.[1] ?? "", prompt)) {
      const download = document.createElement("button");
      download.className = "code-download";
      download.type = "button";
      download.textContent = "Download";
      download.addEventListener("click", () => {
        const source = code?.textContent ?? "";
        if (!source) {
          showToast("This code block is empty and cannot be downloaded.");
          return;
        }
        const filename = codeBlockFilename(pre, languageMatch?.[1] ?? "", prompt);
        const mimeType = codeMimeType(languageMatch?.[1] ?? "");
        try {
          const blob = new Blob([source], { type: `${mimeType};charset=utf-8` });
          const url = URL.createObjectURL(blob);
          const anchor = document.createElement("a");
          anchor.href = url;
          anchor.download = filename;
          anchor.hidden = true;
          document.body.append(anchor);
          anchor.click();
          anchor.remove();
          window.setTimeout(() => URL.revokeObjectURL(url), 1000);
          showToast(`Downloaded ${filename}.`);
        } catch {
          showToast("The code file could not be downloaded.");
        }
      });
      actions.append(download);
    }
    toolbar.append(language, actions);
    pre.prepend(toolbar);
  }
}

function codeBlockFilename(pre, language, prompt) {
  const label = pre.previousElementSibling?.textContent ?? "";
  const namedInResponse = label.match(/\bFile:\s*([^\s`*]+)/i)?.[1];
  const namedInPrompt = filenameFromPrompt(prompt);
  const extension = codeFileTypes[normalizeCodeLanguage(language)]?.extension ?? "txt";
  const defaultFilename = codeFileTypes[normalizeCodeLanguage(language)]?.filename ?? "code.txt";
  const blockIndex = codeBlockIndex(pre);
  const fallback = blockIndex > 0
    ? defaultFilename.replace(/(\.[^.]+)$/, `-${blockIndex + 1}$1`)
    : defaultFilename;
  const matchingLanguageFileCount = [...pre.parentElement.querySelectorAll("pre")].filter((block) => {
    const blockLanguage = block.querySelector("code")?.className.match(/(?:^|\s)language-([A-Za-z0-9_+.-]+)/)?.[1] ?? "";
    return normalizeCodeLanguage(blockLanguage) === normalizeCodeLanguage(language)
      && isDownloadableCodeBlock(block, blockLanguage, prompt);
  }).length;
  const requestedExtension = namedInPrompt.split(".").pop()?.toLowerCase() ?? "";
  const requestedLanguage = Object.entries(codeFileTypes)
    .find(([, type]) => type.extension === requestedExtension)?.[0];
  const candidate = namedInPrompt && requestedLanguage === normalizeCodeLanguage(language) && matchingLanguageFileCount === 1
    ? namedInPrompt
    : namedInResponse ?? namedInPrompt ?? fallback;
  const basename = candidate.replace(/\\/g, "/").split("/").pop() ?? fallback;
  const safeName = basename.replace(/[^A-Za-z0-9._-]/g, "_").replace(/^\.+/, "");
  return safeName || fallback;
}

function isDownloadableCodeBlock(pre, language, prompt) {
  const label = pre.previousElementSibling?.textContent.trim() ?? "";
  if (/^File:\s*\S+/i.test(label)) return true;

  const normalizedLanguage = normalizeCodeLanguage(language);
  const expectedFilename = filenameFromPrompt(prompt);
  if (expectedFilename) {
    const extension = expectedFilename.split(".").pop()?.toLowerCase() ?? "";
    const expectedLanguage = Object.entries(codeFileTypes)
      .find(([, type]) => type.extension === extension)?.[0];
    return expectedLanguage ? normalizedLanguage === expectedLanguage : false;
  }

  const requestedLanguages = Object.keys(codeFileTypes).filter((candidate) => {
    const aliases = {
      javascript: "javascript|js",
      typescript: "typescript|ts",
      markdown: "markdown|md",
    };
    const terms = aliases[candidate] ?? candidate;
    return new RegExp(`\\b(?:${terms})\\b`, "i").test(prompt);
  });
  if (requestedLanguages.length) return requestedLanguages.includes(normalizedLanguage);

  const nonFileLanguages = new Set([
    "bash", "shell", "sh", "console", "terminal", "text", "plaintext", "output",
  ]);
  if (nonFileLanguages.has(normalizedLanguage)) return false;
  const firstFileBlock = [...pre.parentElement.querySelectorAll("pre")].find((block) => {
    const blockLanguage = normalizeCodeLanguage(
      block.querySelector("code")?.className.match(/(?:^|\s)language-([A-Za-z0-9_+.-]+)/)?.[1] ?? "",
    );
    return !nonFileLanguages.has(blockLanguage);
  });
  return firstFileBlock === pre;
}

function filenameFromPrompt(prompt) {
  return prompt.match(
    /\b(?:filename|file\s+(?:named|called)|save(?:\s+it)?\s+as|download(?:\s+it)?\s+as|named|called)\s*(?:is\s*)?[:=]?\s*[`"'“‘]?([A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,10})/i,
  )?.[1] ?? "";
}

function codeBlockIndex(pre) {
  return [...pre.parentElement.querySelectorAll("pre")].indexOf(pre);
}

function normalizeCodeLanguage(language) {
  const normalized = language.toLowerCase();
  if (normalized === "js" || normalized === "node") return "javascript";
  if (normalized === "py") return "python";
  if (normalized === "ts") return "typescript";
  if (normalized === "htm") return "html";
  if (normalized === "md") return "markdown";
  if (normalized === "sh" || normalized === "shell") return normalized;
  return normalized;
}

const codeFileTypes = {
  python: { extension: "py", filename: "main.py", mime: "text/x-python" },
  html: { extension: "html", filename: "index.html", mime: "text/html" },
  css: { extension: "css", filename: "styles.css", mime: "text/css" },
  javascript: { extension: "js", filename: "script.js", mime: "text/javascript" },
  typescript: { extension: "ts", filename: "index.ts", mime: "text/typescript" },
  json: { extension: "json", filename: "data.json", mime: "application/json" },
  markdown: { extension: "md", filename: "README.md", mime: "text/markdown" },
  sql: { extension: "sql", filename: "query.sql", mime: "application/sql" },
  go: { extension: "go", filename: "main.go", mime: "text/x-go" },
  rust: { extension: "rs", filename: "main.rs", mime: "text/plain" },
  java: { extension: "java", filename: "Main.java", mime: "text/x-java-source" },
  c: { extension: "c", filename: "main.c", mime: "text/x-c" },
  cpp: { extension: "cpp", filename: "main.cpp", mime: "text/x-c++" },
  ruby: { extension: "rb", filename: "main.rb", mime: "text/x-ruby" },
  php: { extension: "php", filename: "index.php", mime: "application/x-httpd-php" },
  swift: { extension: "swift", filename: "main.swift", mime: "text/x-swift" },
  kotlin: { extension: "kt", filename: "Main.kt", mime: "text/plain" },
};

function codeMimeType(language) {
  return codeFileTypes[normalizeCodeLanguage(language)]?.mime ?? "text/plain";
}

function updateGenerationControls() {
  const generating = activeGeneration !== null;
  stopButton.hidden = !generating;
  topbarStopButton.hidden = !generating;
  sendButton.hidden = generating;
  sendButton.disabled = generating || !messageInput.value.trim();
  messageInput.setAttribute("aria-busy", String(generating));
}

function resizeInput() {
  messageInput.style.height = "auto";
  messageInput.style.height = `${Math.min(messageInput.scrollHeight, window.innerWidth <= 760 ? 140 : 190)}px`;
  updateGenerationControls();
}

function titleFromFirstMessage(text) {
  const normalized = text.replace(/\s+/g, " ").trim();
  return normalized.length > 48 ? `${normalized.slice(0, 47).trimEnd()}…` : normalized;
}

async function sendMessage(text = messageInput.value.trim(), retryMessageId = null) {
  if ((!text && !retryMessageId) || activeGeneration) return;
  const chat = currentChat();
  let userMessage;
  if (retryMessageId) {
    const failedIndex = chat.messages.findIndex((message) => message.id === retryMessageId && message.status === "failed");
    if (failedIndex < 0) return;
    chat.messages.splice(failedIndex);
    userMessage = chat.messages.at(-1);
    if (!userMessage || userMessage.role !== "user") {
      showToast("This response cannot be retried from the saved conversation.");
      return;
    }
  } else {
    userMessage = {
      id: makeId(),
      role: "user",
      content: text,
      status: "complete",
      createdAt: Date.now(),
    };
    chat.messages.push(userMessage);
    if (chat.messages.filter((message) => message.role === "user").length === 1) {
      chat.title = titleFromFirstMessage(text) || "New conversation";
    }
  }
  chat.updatedAt = Date.now();
  if (!conversations.some((conversation) => conversation.id === chat.id)) conversations.unshift(chat);
  const assistant = {
    id: makeId(),
    role: "assistant",
    content: "",
    status: "streaming",
    error: "",
    createdAt: Date.now(),
  };
  chat.messages.push(assistant);
  currentConversation = chat;
  messageInput.value = "";
  resizeInput();
  persist();
  renderConversation({ scroll: true });

  const controller = new AbortController();
  activeGeneration = { controller, chatId: chat.id, assistantId: assistant.id };
  updateGenerationControls();
  try {
    const candidates = chat.messages
      .filter((message) => message.id !== assistant.id && message.status === "complete")
      .map(({ role, content }) => ({ role, content }));
    const messages = [];
    let historyLength = 0;
    for (
      let index = candidates.length - 1;
      index >= 0 && messages.length < MAX_MESSAGES_PER_REQUEST;
      index -= 1
    ) {
      const message = candidates[index];
      if (historyLength + message.content.length > MAX_HISTORY_LENGTH) break;
      messages.unshift(message);
      historyLength += message.content.length;
    }
    const response = await apiFetch("/api/chat/stream", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
      body: JSON.stringify({ messages }),
      signal: controller.signal,
    });
    if (response.status === 401) {
      if (authenticatedUser) handleSessionExpired();
      return;
    }
    if (!response.ok || !response.body) {
      if (response.status !== 422) setModelHealth({ status: "unavailable" });
      throw new Error(response.status === 422
        ? "The conversation is too long to send. Start a new chat and try again."
        : "Luma AI is temporarily unavailable. Please try again.");
    }
    await readEventStream(response.body, (event, payload) => {
      if (event === "token" && typeof payload.text === "string") {
        assistant.content += payload.text;
        updateAssistantMessage(chat, assistant);
        persistSoon();
      } else if (event === "error") {
        if (payload.message !== "The response reached the maximum message length.") {
          setModelHealth({ status: "unavailable" });
        }
        throw new Error(typeof payload.message === "string" ? payload.message : "The response could not be generated.");
      }
    });
    assistant.status = "complete";
    chat.updatedAt = Date.now();
    persist();
    if (currentConversation.id === chat.id) {
      finishAssistantDisplay(chat, assistant);
      renderHistory();
    }
  } catch (error) {
    assistant.status = "failed";
    if (error.name !== "AbortError" && error instanceof TypeError) {
      setModelHealth({ status: "unavailable" });
    }
    assistant.error = error.name === "AbortError"
      ? "Generation stopped."
      : error instanceof TypeError
      ? "Luma AI is temporarily unavailable. Please try again."
        : error.message || "The response could not be generated.";
    chat.updatedAt = Date.now();
    persist();
    if (currentConversation.id === chat.id) {
      const entry = messageNodes.get(assistant.id);
      if (entry) showMessageError(entry, assistant);
      else renderConversation();
    }
  } finally {
    if (activeGeneration?.assistantId === assistant.id) activeGeneration = null;
    updateGenerationControls();
  }
}

async function readEventStream(stream, onEvent) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let doneReceived = false;
  while (true) {
    const { value, done } = await reader.read();
    buffer += decoder.decode(value, { stream: !done });
    let boundary = buffer.indexOf("\n\n");
    while (boundary >= 0) {
      const frame = buffer.slice(0, boundary);
      buffer = buffer.slice(boundary + 2);
      let event = "message";
      let data = "";
      for (const line of frame.split(/\r?\n/)) {
        if (line.startsWith("event:")) event = line.slice(6).trim();
        if (line.startsWith("data:")) data += line.slice(5).trim();
      }
      if (data) onEvent(event, JSON.parse(data));
      if (event === "done") doneReceived = true;
      boundary = buffer.indexOf("\n\n");
    }
    if (done) break;
  }
  if (!doneReceived) throw new Error("The chat server connection ended unexpectedly.");
}

function finishAssistantDisplay(chat, assistant) {
  if (chat.id !== currentConversation.id) return;
  const entry = messageNodes.get(assistant.id);
  if (!entry) {
    renderConversation({ scroll: true });
    return;
  }
  entry.body.classList.remove("streaming-text");
  entry.body.textContent = assistant.content;
  if (assistant.content) requestMarkdown(assistant.id, chat.id, assistant.content);
  keepScrolledToBottom();
}

function startNewChat() {
  closeMenus();
  if (activeGeneration) {
    showToast("Stop the current response before starting a new chat.");
    return;
  }
  currentConversation = makeConversation();
  messageInput.value = "";
  resizeInput();
  renderConversation();
  persist();
  closeDrawer();
  messageInput.focus();
}

function closeDrawer() {
  shell.classList.remove("drawer-open");
}

const ONBOARDING_KEY = "luma.onboarding.completed.v1";
const onboardingSlides = [
  {
    label: "01 — Welcome to Luma AI",
    headline: "A thoughtful space to think.",
    description: "Meet Luma AI, your personal space to explore ideas, solve problems, and discover new possibilities.",
    art: '<svg class="onboarding-sparkle" viewBox="0 0 24 24" fill="currentColor"><path d="M12 1.7 14.7 9l7.6 3-7.6 3-2.7 7.3L9.3 15 1.7 12l7.6-3L12 1.7Z"/></svg>',
  },
  {
    label: "02 — Think Without Limits",
    headline: "Ideas become clearer here.",
    description: "Ask questions, explore concepts, brainstorm, and work through challenging problems in a natural conversation.",
    art: '<span class="illustration-paper paper-one"><i></i><i></i><i></i><i></i></span><span class="illustration-paper paper-two"><i></i><i></i><i></i><i></i></span>',
  },
  {
    label: "03 — Create Something Useful",
    headline: "From ideas to actual work.",
    description: "Get help with code, understand complex topics, create content, and copy or download useful results.",
    art: '<span class="illustration-code"><i></i><i></i><i></i><i></i><i></i></span><span class="illustration-file" aria-hidden="true">↓</span>',
  },
  {
    label: "04 — Your Space, Your Way",
    headline: "Make room for what’s next.",
    description: "Start a conversation, explore new ideas, and make Luma AI part of your workflow.",
    art: '<svg class="illustration-shield" viewBox="0 0 100 112"><path d="M50 7 88 22v29c0 26-16 43-38 54C28 94 12 77 12 51V22L50 7Z"/><path class="shield-sparkle" d="m50 29 5.7 15.3L72 50l-16.3 5.7L50 72l-5.7-16.3L28 50l16.3-5.7L50 29Z"/></svg>',
  },
];

function updateOnboarding(step) {
  onboardingStep = Math.max(0, Math.min(step, onboardingSlides.length - 1));
  const slide = onboardingSlides[onboardingStep];
  document.querySelector("#onboardingStepLabel").textContent = slide.label;
  document.querySelector("#onboardingHeadline").textContent = slide.headline;
  document.querySelector("#onboardingDescription").textContent = slide.description;
  document.querySelector("#onboardingArt").innerHTML = slide.art;
  document.querySelector("#onboardingBack").hidden = onboardingStep === 0;
  document.querySelector("#onboardingNext").textContent =
    onboardingStep === onboardingSlides.length - 1 ? "Get Started" : "Next";
  for (const [index, indicator] of [...document.querySelectorAll("#onboardingProgress span")].entries()) {
    indicator.classList.toggle("active", index === onboardingStep);
    indicator.setAttribute("aria-current", index === onboardingStep ? "step" : "false");
  }
  document.querySelector("#onboardingHeadline").focus();
}

function showOnboarding(step = 0, pushHistory = true) {
  shell.hidden = true;
  authView.hidden = true;
  onboardingView.hidden = false;
  document.querySelectorAll("#authView .auth-card").forEach((panel) => {
    panel.hidden = true;
  });
  updateOnboarding(step);
  if (pushHistory) {
    try {
      history.pushState({ lumaView: "onboarding", step: onboardingStep }, "", location.pathname);
    } catch {}
  }
}

function showAuth(page = "landing", pushHistory = true) {
  shell.hidden = true;
  onboardingView.hidden = true;
  authView.hidden = false;
  for (const panel of ["authLanding", "loginPanel", "registerPanel"]) {
    document.querySelector(`#${panel}`).hidden = panel !== ({
      landing: "authLanding",
      login: "loginPanel",
      register: "registerPanel",
    }[page] ?? "authLanding");
  }
  const loginMsg = document.querySelector("#loginMessage");
  if (loginMsg) loginMsg.textContent = "";
  const regMsg = document.querySelector("#registerMessage");
  if (regMsg) regMsg.textContent = "";
  if (page !== "landing") {
    showAuthMessage("");
  }
  if (pushHistory) {
    try {
      history.pushState({ lumaView: "auth", page }, "", location.pathname);
    } catch {}
  }
}

function onboardingCompleted() {
  try {
    return localStorage.getItem(ONBOARDING_KEY) === "true";
  } catch {
    return false;
  }
}

function completeOnboarding() {
  try {
    localStorage.setItem(ONBOARDING_KEY, "true");
  } catch {
    document.querySelector("#authConnectionMessage").textContent =
      "Your browser could not save this preference. You may see the introduction again.";
    document.querySelector("#authConnectionMessage").hidden = false;
  }
  showAuth("landing");
}

function showAuthMessage(message, kind = "error") {
  const element = document.querySelector("#authConnectionMessage");
  if (!element) return;
  element.textContent = message;
  element.dataset.kind = kind;
  element.hidden = !message;
}

function showChat(user, pushHistory = false) {
  if (!user || typeof user !== "object") {
    showAuth("landing", false);
    return;
  }
  authenticatedUser = user;
  conversations = loadConversations();
  currentConversation =
    findConversation(readStorage(accountStorageKey(CURRENT_CHAT_KEY))) ?? makeConversation();
  const profileEl = document.querySelector("#profileName");
  if (profileEl) profileEl.textContent = user.full_name || "User";
  shell.hidden = false;
  onboardingView.hidden = true;
  authView.hidden = true;
  document.querySelectorAll("#authView .auth-card").forEach((panel) => {
    panel.hidden = true;
  });
  renderConversation();
  renderHistory();
  try {
    if (pushHistory) {
      history.pushState({ lumaView: "chat" }, "", location.pathname);
    } else {
      history.replaceState({ lumaView: "chat" }, "", location.pathname);
    }
  } catch {}
  window.clearInterval(healthInterval);
  checkModelHealth();
  healthInterval = window.setInterval(checkModelHealth, 20_000);
}

async function initializeExperience() {
  try {
    const response = await apiFetch("/api/auth/me", {
      cache: "no-store",
    });
    if (response.ok) {
      showChat(await response.json());
      return;
    }
    if (response.status !== 401) throw new Error("Authentication service unavailable.");
    try {
      history.replaceState(null, "", location.pathname);
    } catch {}
    if (onboardingCompleted()) {
      showAuth("landing", false);
      showAuthMessage("Please log in to continue.");
    }
    else showOnboarding(0, false);
  } catch {
    try {
      history.replaceState(null, "", location.pathname);
    } catch {}
    if (onboardingCompleted()) {
      showAuth("landing", false);
      showAuthMessage("Unable to reach Luma AI. Check that the server is running and try again.");
    } else {
      showOnboarding(0, false);
    }
  }
}

function handleExperiencePopState(event) {
  if (authenticatedUser) {
    if (event.state?.lumaView === "auth") {
      authenticatedUser = null;
      conversations = [];
      currentConversation = makeConversation();
      window.clearInterval(healthInterval);
      showAuth(event.state.page ?? "landing", false);
    } else if (event.state?.lumaView === "onboarding") {
      showOnboarding(event.state.step ?? 0, false);
    } else {
      shell.hidden = false;
      onboardingView.hidden = true;
      authView.hidden = true;
    }
    return;
  }
  if (event.state?.lumaView === "onboarding") {
    showOnboarding(event.state.step ?? 0, false);
  } else if (event.state?.lumaView === "auth") {
    showAuth(event.state.page ?? "landing", false);
  } else if (onboardingCompleted()) {
    showAuth("landing", false);
  } else {
    showOnboarding(0, false);
  }
}

function passwordToggle(button) {
  const input = document.querySelector(`#${button.dataset.passwordToggle}`);
  const show = input.type === "password";
  input.type = show ? "text" : "password";
  button.textContent = show ? "Hide" : "Show";
  button.setAttribute("aria-label", `${show ? "Hide" : "Show"} password`);
  button.setAttribute("aria-pressed", String(show));
}

async function submitAuthForm({ form, submit, message, endpoint, successMessage }) {
  const messageElement = document.querySelector(message);
  const submitButton = document.querySelector(submit);
  if (messageElement) messageElement.textContent = "";
  // Always clear any global auth connection message so the form has one clear error location
  showAuthMessage("");

  if (!form.reportValidity()) {
    if (messageElement) messageElement.textContent = "Check the highlighted fields and try again.";
    return;
  }
  if (form.id === "registerForm") {
    const password = form.elements.password.value;
    if (password !== form.elements.password_confirm.value) {
      if (messageElement) messageElement.textContent = "The passwords do not match.";
      form.elements.password_confirm.focus();
      return;
    }
  }
  const previousText = submitButton.textContent;
  submitButton.disabled = true;
  submitButton.textContent = endpoint.endsWith("register") ? "Creating account…" : "Logging in…";

  try {
    const payload = Object.fromEntries(new FormData(form).entries());
    delete payload.password_confirm;

    let response;
    try {
      response = await apiFetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
    } catch (networkError) {
      console.warn("Luma AI connection error:", networkError);
      if (messageElement) {
        messageElement.textContent = "Unable to reach Luma AI. Check that the server is running and try again.";
      }
      return;
    }

    let result = null;
    try {
      result = await response.json();
    } catch {}

    if (!response.ok) {
      if (response.status === 401) {
        if (messageElement) messageElement.textContent = "Email or password is incorrect.";
      } else if (response.status === 409) {
        if (messageElement) messageElement.textContent = "Unable to create an account with this email. Try logging in instead.";
      } else if (response.status === 422) {
        let validationMsg = "Please check your input and try again.";
        if (result && Array.isArray(result.detail) && result.detail.length > 0) {
          const firstErr = result.detail[0];
          const rawMsg = firstErr.msg || "";
          validationMsg = rawMsg.replace(/^Value error,\s*/i, "").trim() || validationMsg;
        } else if (result && typeof result.detail === "string") {
          validationMsg = result.detail;
        }
        if (messageElement) messageElement.textContent = validationMsg;
      } else if (response.status === 429) {
        if (messageElement) messageElement.textContent = "Too many sign-in attempts. Please try again later.";
      } else if (response.status === 403) {
        if (messageElement) messageElement.textContent = "This request could not be verified. Please refresh and try again.";
      } else if (response.status >= 500) {
        console.error("Luma AI server error:", response.status, result);
        if (messageElement) messageElement.textContent = "Luma AI encountered a server error. Please try again later.";
      } else {
        if (messageElement) {
          messageElement.textContent = (result && typeof result.detail === "string")
            ? result.detail
            : "Luma AI could not complete your request. Please try again.";
        }
      }
      return;
    }

    form.reset();
    showChat(result);
    showToast(successMessage);
  } catch (error) {
    console.error("Authentication error:", error);
    if (messageElement) {
      messageElement.textContent = "Unable to reach Luma AI. Check that the server is running and try again.";
    }
  } finally {
    submitButton.disabled = false;
    submitButton.textContent = previousText;
  }
}

async function logout() {
  if (activeGeneration) stopGeneration();
  try {
    const response = await apiFetch("/api/auth/logout", {
      method: "POST",
    });
    if (!response.ok) throw new Error("Logout failed.");
  } catch {
    showToast("Luma AI could not log you out. Please try again.");
    return;
  }
  authenticatedUser = null;
  conversations = [];
  currentConversation = makeConversation();
  messageNodes.clear();
  window.clearInterval(healthInterval);
  settingsDialog.close();
  showAuth("landing");
}

function setConnectionStatus(status) {
  const statusLabels = {
    connecting: "Connecting…",
    online: "Online",
    offline: "Offline",
  };
  document.querySelector("#topbarModelStatus").textContent = statusLabels[status];
  for (const dot of [
    document.querySelector("#topbarStatusDot"),
    document.querySelector("#settingsStatusDot"),
  ]) {
    dot.classList.toggle("online", status === "online");
    dot.classList.toggle("offline", status === "offline");
    dot.classList.toggle("checking", status === "connecting");
  }
}

function setModelHealth(health) {
  if (typeof health?.model === "string" && health.model) {
    document.querySelector("#settingsModelName").textContent = health.model;
  }
  const online = health?.ollama_connected === true && health?.model_available === true;
  setConnectionStatus(online ? "online" : "offline");
}

function handleSessionExpired() {
  if (!authenticatedUser) return;
  if (activeGeneration) activeGeneration.controller.abort();
  activeGeneration = null;
  authenticatedUser = null;
  conversations = [];
  currentConversation = makeConversation();
  messageNodes.clear();
  window.clearInterval(healthInterval);
  healthInterval = 0;
  if (settingsDialog.open) settingsDialog.close();
  showAuth("landing");
  showAuthMessage("Your session has expired. Please log in again.");
}

async function checkModelHealth() {
  const user = authenticatedUser;
  if (!user) return;
  setConnectionStatus("connecting");
  try {
    const response = await apiFetch("/api/health/ai", {
      cache: "no-store",
    });
    if (response.status === 401) {
      if (authenticatedUser?.id === user.id) handleSessionExpired();
      return;
    }
    if (!response.ok) throw new Error("health");
    if (authenticatedUser?.id !== user.id) return;
    setModelHealth(await response.json());
  } catch {
    if (authenticatedUser?.id === user.id) setConnectionStatus("offline");
  }
}

function toggleSearch() {
  const searchBox = document.querySelector("#searchBox");
  const open = searchBox.hidden;
  closeMenus();
  searchBox.hidden = !open;
  shell.classList.toggle("search-open", open);
  if (open) {
    searchInput.focus();
  } else {
    searchInput.value = "";
    renderHistory();
  }
}

function toggleMenu(button, menu) {
  const open = menu.hidden;
  closeMenus();
  if (open) {
    menu.hidden = false;
    button.setAttribute("aria-expanded", "true");
  }
}

function closeMenus() {
  for (const [buttonId, menuId] of [
    ["headerMoreButton", "headerMenu"],
    ["historyMoreButton", "historyMenu"],
  ]) {
    document.querySelector(`#${menuId}`).hidden = true;
    document.querySelector(`#${buttonId}`).setAttribute("aria-expanded", "false");
  }
}

function closeHistoryMenu() {
  document.querySelector("#historyMenu").hidden = true;
  document.querySelector("#historyMoreButton").setAttribute("aria-expanded", "false");
}

function openSettings() {
  closeMenus();
  settingsDialog.showModal();
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    showToast("Copied to clipboard.");
  } catch {
    showToast("Clipboard access is unavailable in this browser.");
  }
}

historyList.addEventListener("click", (event) => {
  const item = event.target.closest(".history-item");
  if (!item) return;
  const chat = findConversation(item.dataset.chatId);
  if (!chat) return;
  const action = event.target.closest("[data-action]")?.dataset.action;
  if (action === "rename") {
    const title = window.prompt("Rename conversation", chat.title);
    if (title === null) return;
    const cleaned = title.trim();
    if (!cleaned) {
      showToast("A conversation title cannot be empty.");
      return;
    }
    chat.title = cleaned.slice(0, 80);
    persist();
    if (currentConversation.id === chat.id) conversationTitle.textContent = chat.title;
    return;
  }
  if (action === "delete") {
    if (!window.confirm(`Delete “${chat.title}”? This cannot be undone.`)) return;
    if (activeGeneration?.chatId === chat.id) stopGeneration();
    conversations = conversations.filter((conversation) => conversation.id !== chat.id);
    if (currentConversation.id === chat.id) currentConversation = makeConversation();
    persist();
    renderConversation();
    return;
  }
  if (chat) {
    currentConversation = chat;
    renderConversation({ scroll: true });
    closeDrawer();
  }
});

messagesEl.addEventListener("click", (event) => {
  const copyButton = event.target.closest(".copy-message");
  if (copyButton) {
    const message = currentChat().messages.find((item) => item.id === copyButton.dataset.messageId);
    if (message) copyText(message.content);
    return;
  }
  const retryButton = event.target.closest("[data-retry-message-id]");
  if (retryButton) sendMessage("", retryButton.dataset.retryMessageId);
});

messagesEl.addEventListener("click", (event) => {
  const link = event.target.closest("a[href]");
  if (!link) return;
  event.preventDefault();
  if (!/^https?:$/.test(new URL(link.href).protocol) && !link.href.startsWith("mailto:")) {
    showToast("This link type is not allowed.");
    return;
  }
  if (window.confirm(`Open this link in a new tab?\n${link.href}`)) {
    window.open(link.href, "_blank", "noopener,noreferrer");
  }
});

composerForm.addEventListener("submit", (event) => {
  event.preventDefault();
  sendMessage();
});
messageInput.addEventListener("input", resizeInput);
messageInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    composerForm.requestSubmit();
  }
});

function stopGeneration() {
  activeGeneration?.controller.abort();
}

stopButton.addEventListener("click", stopGeneration);
topbarStopButton.addEventListener("click", stopGeneration);
document.querySelector("#newChatButton").addEventListener("click", startNewChat);
document.querySelector("#topbarNewChat").addEventListener("click", startNewChat);
document.querySelector("#collapseSidebar").addEventListener("click", () => shell.classList.add("sidebar-collapsed"));
document.querySelector("#expandSidebar").addEventListener("click", () => shell.classList.remove("sidebar-collapsed"));
document.querySelector("#openSidebar").addEventListener("click", () => shell.classList.add("drawer-open"));
document.querySelector("#drawerScrim").addEventListener("click", closeDrawer);
searchInput.addEventListener("input", renderHistory);
document.querySelector("#headerSearchButton").addEventListener("click", toggleSearch);
document.querySelector("#settingsButton").addEventListener("click", openSettings);
document.querySelector("#settingsNavButton").addEventListener("click", openSettings);
document.querySelector("#chatNavButton").addEventListener("click", closeDrawer);
document.querySelector("#historyMoreButton").addEventListener("click", (event) => {
  toggleMenu(event.currentTarget, document.querySelector("#historyMenu"));
});
document.querySelector("#headerMoreButton").addEventListener("click", (event) => {
  toggleMenu(event.currentTarget, document.querySelector("#headerMenu"));
});
document.querySelector("#clearHistoryMenuButton").addEventListener("click", () => {
  closeMenus();
  document.querySelector("#clearHistoryButton").click();
});
document.querySelector("#headerNewChatButton").addEventListener("click", startNewChat);
document.querySelector("#headerSettingsButton").addEventListener("click", openSettings);
document.addEventListener("click", (event) => {
  if (!event.target.closest(".recent-heading") && !event.target.closest(".topbar-actions")) {
    closeMenus();
  }
});
document.querySelector("#closeSettings").addEventListener("click", () => settingsDialog.close());
settingsDialog.addEventListener("click", (event) => {
  if (event.target === settingsDialog) settingsDialog.close();
});
document.querySelector("#clearHistoryButton").addEventListener("click", () => {
  if (!conversations.length) {
    showToast("There are no conversations to clear.");
    return;
  }
  if (!window.confirm("Clear all saved conversations? This cannot be undone.")) return;
  stopGeneration();
  conversations = [];
  currentConversation = makeConversation();
  persist();
  renderConversation();
  settingsDialog.close();
  showToast("Conversation history cleared.");
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    startNewChat();
  }
  if (event.key === "/" && document.activeElement === document.body) {
    event.preventDefault();
    if (document.querySelector("#searchBox").hidden) toggleSearch();
    else searchInput.focus();
  }
  if (event.key === "Escape") closeDrawer();
});
window.addEventListener("beforeunload", () => {
  window.clearTimeout(saveTimeout);
  persist();
});
window.addEventListener("resize", resizeInput);

document.querySelector("#skipOnboarding").addEventListener("click", completeOnboarding);
document.querySelector("#onboardingNext").addEventListener("click", () => {
  if (onboardingStep === onboardingSlides.length - 1) completeOnboarding();
  else showOnboarding(onboardingStep + 1);
});
document.querySelector("#onboardingBack").addEventListener("click", () => {
  showOnboarding(onboardingStep - 1);
});
document.querySelector("#openLogin").addEventListener("click", () => showAuth("login"));
document.querySelector("#openRegister").addEventListener("click", () => showAuth("register"));
document.querySelector("#loginBack").addEventListener("click", () => showAuth("landing"));
document.querySelector("#registerBack").addEventListener("click", () => showAuth("landing"));
document.querySelector("#loginToRegister").addEventListener("click", () => showAuth("register"));
document.querySelector("#registerToLogin").addEventListener("click", () => showAuth("login"));
document.querySelector("#logoutButton").addEventListener("click", logout);
document.querySelector("#loginForm").addEventListener("submit", (event) => {
  event.preventDefault();
  submitAuthForm({
    form: event.currentTarget,
    submit: "#loginSubmit",
    message: "#loginMessage",
    endpoint: "/api/auth/login",
    successMessage: "Welcome back.",
  });
});
document.querySelector("#registerForm").addEventListener("submit", (event) => {
  event.preventDefault();
  submitAuthForm({
    form: event.currentTarget,
    submit: "#registerSubmit",
    message: "#registerMessage",
    endpoint: "/api/auth/register",
    successMessage: "Your account is ready. Welcome to Luma AI.",
  });
});
document.querySelectorAll("[data-password-toggle]").forEach((button) => {
  button.addEventListener("click", () => passwordToggle(button));
});
window.addEventListener("popstate", handleExperiencePopState);
initializeExperience();
