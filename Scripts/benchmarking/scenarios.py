"""Deterministic sample messages and the expectations that verify them."""

from __future__ import annotations

import time
import uuid

REFERENCE_DATE_OFFSET = 978_307_200  # 2001-01-01 in Unix time
OBJECT_REPLACEMENT = "\ufffc"


def _stamp(offset: float = 0.0) -> float:
    return time.time() - REFERENCE_DATE_OFFSET + offset


def _message(role: str, content: str, offset: float = 0.0, state: str = "complete") -> dict:
    return {
        "id": str(uuid.uuid4()),
        "role": role,
        "content": content,
        "createdAt": _stamp(offset),
        "state": state,
        "attachments": [],
        "completedAt": _stamp(offset + 1) if role == "assistant" else None,
    }


LONG_TEXT_TOPICS = [
    (
        "Queueing latency",
        "Requests arrive in bursts and the scheduler drains them in admission order. "
        "When the arrival rate approaches the service capacity, the waiting time grows "
        "without bound even though each individual job still finishes quickly. "
    ),
    (
        "Cache placement",
        "Each shard keeps a local window of recent entries and evicts the least recently "
        "used item when the window is full. Placement decisions are made from the request "
        "key alone, so a hot key always lands on the same shard. "
    ),
    (
        "Retry budget",
        "A client retries at most three times with exponential backoff and jitter. "
        "The budget is shared across every endpoint, which prevents a single failing "
        "route from consuming the whole allowance during an incident. "
    ),
]

LONG_TEXT_FILLER = (
    "Operators review these parameters during every capacity planning cycle and record "
    "the observed distribution so the next review starts from measurements instead of "
    "assumptions. "
)


def long_text_body(word_target: int = 1200) -> str:
    words = []
    index = 0
    while len(words) < word_target:
        topic, paragraph = LONG_TEXT_TOPICS[index % len(LONG_TEXT_TOPICS)]
        words.extend(f"## {topic}".split())
        words.extend(paragraph.split())
        words.extend(LONG_TEXT_FILLER.split())
        index += 1
    body_words = words[:word_target]

    paragraphs = [" ".join(body_words[start:start + 60]) for start in range(0, len(body_words), 60)]
    return (
        "Long text marker LT-ALPHA.\n\n"
        "## Summary\n\n"
        + "\n\n".join(paragraphs)
        + "\n\n| Metric | Observed | Bound |\n| --- | --- | --- |\n"
        "| p50 latency | 42 ms | 120 ms |\n| p99 latency | 180 ms | 400 ms |\n\n"
        "```swift\nlet budget = 3\nfunc retry(_ attempt: Int) -> Bool { attempt < budget }\n```\n\n"
        "End of long text marker LT-OMEGA."
    )


def normal_long_text():
    body = long_text_body()
    return {
        "name": "normal_long_text",
        "messages": [
            _message("user", "Summarize the capacity planning notes in long form."),
            _message("assistant", body, offset=1),
        ],
        "expect_texts": ["Long text marker LT-ALPHA"],
        "expanded_expect_texts": ["End of long text marker LT-OMEGA"],
        "expect_formulas": [],
        "sample": {
            "words": len(body.split()),
            "formulas": 0,
            "characters": len(body),
        },
    }


INLINE_TEX = "E = mc^2"
DISPLAY_TEX = r"\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}"


def single_math():
    body = (
        "The mass-energy equivalence equation is $E = mc^2$, published by Einstein in 1905.\n\n"
        "A derived form follows:\n\n"
        "$$" + DISPLAY_TEX + "$$\n\n"
        "Closing inline case $a^2 + b^2 = c^2$ stays inside this sentence."
    )
    return {
        "name": "single_math_1",
        "messages": [
            _message("user", "What is the mass-energy equivalence equation?"),
            _message("assistant", body, offset=1),
        ],
        "expect_texts": [
            # The object-replacement character sits inside one text run: the
            # inline formula stayed inside the sentence instead of becoming a
            # block of its own.
            "The mass-energy equivalence equation is " + OBJECT_REPLACEMENT + ", published by Einstein in 1905.",
            "Closing inline case " + OBJECT_REPLACEMENT + " stays inside this sentence.",
        ],
        "expect_formulas": [DISPLAY_TEX],
        "sample": {
            "words": len(body.split()),
            "formulas": 3,
            "characters": len(body),
        },
    }


WIDE_TEX = (
    r"\sum_{i=1}^{n} \frac{\partial^2 u_i}{\partial x^2} + "
    r"\sum_{j=1}^{m} \frac{\partial^2 u_j}{\partial y^2} + "
    r"\prod_{k=1}^{p} \left(1 + \frac{x_k}{k}\right) + "
    r"\int_{0}^{T} \int_{\Omega} \rho\, \mathbf{u} \cdot \nabla \mathbf{u}\, dx\, dt = "
    r"\mathcal{F}(u, v, w, \theta)"
)


def wide_math():
    body = "A single wide formula for the narrow-window scroll check:\n\n$$" + WIDE_TEX + "$$\n\nClosing line."
    return {
        "name": "wide_math",
        "messages": [
            _message("user", "Show the wide operator."),
            _message("assistant", body, offset=1),
        ],
        "expect_texts": ["Closing line."],
        "expect_formulas": [WIDE_TEX],
        "sample": {"words": len(body.split()), "formulas": 1, "characters": len(body)},
    }


MIXED_TEX_9 = r"G_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}"
MIXED_TEX_19 = r"\frac{\partial u}{\partial t} = \alpha \nabla^2 u"


def mixed_math(count: int = 20):
    messages = [_message("user", "Walk through twenty mathematical topics.")]
    for index in range(1, count + 1):
        if index % 2 == 1:
            tex = MIXED_TEX_9 if index == 9 else (MIXED_TEX_19 if index == 19 else rf"f_{{{index}}}(x) = x^{{{index}}} + 1")
            body = (
                f"### Topic {index} Mathematical Analysis\n\n"
                f"The primary relation is $E = mc^2$ and it is discussed inline.\n\n"
                f"$${tex}$$\n\n"
                f"This system exhibits stability under initial boundary conditions (topic {index})."
            )
        else:
            body = (
                f"### Topic {index} Mathematical Analysis\n\n"
                "This topic is prose only so the mixed matrix keeps plain paragraphs between formulas. "
                "It still exercises list rendering:\n\n"
                "- first item\n- second item\n\n"
                f"Topic {index} closing remark."
            )
        messages.append(_message("assistant", body, offset=index))
        messages.append(_message("user", f"Topic {index + 1}: continue the derivation.", offset=index + 0.5))

    return {
        "name": "mixed_math_20",
        "messages": messages,
        "expect_texts": ["Topic 19 Mathematical Analysis", "Topic 20 Mathematical Analysis"],
        "expect_formulas": [MIXED_TEX_9, MIXED_TEX_19, "f_{1}(x)"],
        "sample": {
            "words": len(" ".join(m["content"] for m in messages if m["role"] == "assistant").split()),
            "formulas": 10,
            "characters": len("".join(m["content"] for m in messages if m["role"] == "assistant")),
        },
    }


def heavy_math(count: int = 50):
    messages = [_message("user", "Derive fifty heavy formulas.")]
    for index in range(1, count + 1):
        tex = rf"heavy_{{{index}}}(x) = \sum_{{k=1}}^{{{index}}} k\,x^{{k}} + \int_0^{{1}} t^{{{index}}}\,dt"
        body = (
            f"### Topic {index} Heavy Formula\n\n"
            f"$${tex}$$\n\n"
            f"Heavy topic {index} closing paragraph."
        )
        messages.append(_message("assistant", body, offset=index))
        messages.append(_message("user", f"Heavy follow-up {index}.", offset=index + 0.5))

    return {
        "name": "heavy_math_50",
        "messages": messages,
        "expect_texts": [f"Topic {count} Heavy Formula", f"Heavy topic {count} closing paragraph"],
        "expect_formulas": [f"heavy_{{{count}}}(x)"],
        "sample": {
            "words": len(" ".join(m["content"] for m in messages if m["role"] == "assistant").split()),
            "formulas": count,
            "characters": len("".join(m["content"] for m in messages if m["role"] == "assistant")),
        },
    }


# Fixture used by the narrow-window scroll evidence, not part of the matrix.
SCENARIOS = {
    "wide_math": wide_math,
    "normal_long_text": normal_long_text,
    "single_math_1": single_math,
    "mixed_math_20": mixed_math,
    "heavy_math_50": heavy_math,
}

MEASURED_SCENARIOS = ["normal_long_text", "single_math_1", "mixed_math_20", "heavy_math_50"]


def lifecycle_messages(cycle: int) -> dict:
    tex = rf"cycle_{{{cycle}}}(x) = x^{{{cycle}}} + \frac{{1}}{{{cycle}}}"
    return {
        "cycle": cycle,
        "tex_fragment": f"cycle_{{{cycle}}}(x)",
        "messages": [
            _message("user", f"Cycle {cycle} user question marker C{cycle}Q."),
            _message(
                "assistant",
                f"Cycle {cycle} answer marker C{cycle}A.\n\n$${tex}$$\n\nCycle {cycle} closing marker C{cycle}Z.",
                offset=1,
            ),
        ],
    }


STREAM_CHUNKS = [
    "Stream start marker ST-BEGIN.\n\n",
    "The identity $E = mc^2$ arrives while the answer is still streaming.\n\n",
    "$$\\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}$$\n\n",
    "Trailing prose keeps the paragraph open ",
    "and arrives in several small chunks ",
    "so the throttled flush runs repeatedly ",
    "while the reader scrolls ",
    "and the answer keeps growing ",
    "until the stream ends with marker ST-END.",
]

SELECTION_BEFORE = "Selection start marker ALPHA sits in the paragraph before the formula."
SELECTION_AFTER = "Selection end marker OMEGA sits after the formula."
SELECTION_MATH = "\\int_{0}^{1} x\\,dx = \\frac{1}{2}"

# Two paragraphs so a drag spans two accessibility elements, and the link
# definition sits *after* the display block, which is where splitting the body
# used to lose it.
LINK_START = "Read [the guide][guide] before continuing."
LINK_DRAG_END = "A closing line gives the drag somewhere to end."
LINK_MARKDOWN = (
    f"{LINK_START}\n\n"
    f"{LINK_DRAG_END}\n\n"
    "$$x^2 + y^2 = z^2$$\n\n"
    "[guide]: https://example.com/guide"
)
LINK_EXPECTED = "[the guide](https://example.com/guide)"


def selection_message() -> dict:
    content = f"{SELECTION_BEFORE}\n\n$${SELECTION_MATH}$$\n\n{SELECTION_AFTER}"
    return {
        "name": "selection",
        "sample": {"words": len(content.split()), "formulas": 1, "characters": len(content)},
        "messages": [
            _message("user", "Explain the derivation."),
            _message("assistant", content, offset=1),
        ],
    }


def link_message() -> dict:
    return {
        "name": "link",
        "sample": {
            "words": len(LINK_MARKDOWN.split()),
            "formulas": 1,
            "characters": len(LINK_MARKDOWN),
        },
        "messages": [
            _message("user", "Where is the guide?"),
            _message("assistant", LINK_MARKDOWN, offset=1),
        ],
    }
