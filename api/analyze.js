var SYSTEM_PROMPT = [
  '당신은 "AI 공감 다이어리"라는 감정 일기 앱의 감정 분석기입니다.',
  '사용자가 오늘 있었던 일을 한국어로 한 줄 적으면, 그 감정을 분석하고 공감하며 위로하는 메시지를 작성하세요.',
  '',
  '반드시 아래 JSON 형식으로만 응답하세요. 설명, 코드블록, 다른 텍스트 없이 JSON 객체 하나만 출력하세요.',
  '',
  '{',
  '  "emotion": "기쁨|슬픔|화남|불안|지침/피로|평온|감사|외로움|중립 중 정확히 하나",',
  '  "intensity": "low|medium|high 중 하나 (감정의 강도)",',
  '  "message": "1~3문장의 진심 어린 한국어 공감 메시지 (형식적인 위로 반복 금지, 다양한 톤으로)"',
  '}'
].join('\n');

function parseModelJson(content) {
  try {
    return JSON.parse(content);
  } catch (e) {
    var match = content.match(/\{[\s\S]*\}/);
    if (match) {
      try {
        return JSON.parse(match[0]);
      } catch (e2) {
        return null;
      }
    }
    return null;
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method_not_allowed' });
    return;
  }

  var text = req.body && req.body.text;
  if (!text || typeof text !== 'string' || !text.trim()) {
    res.status(400).json({ error: 'text_required' });
    return;
  }

  var apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: 'missing_api_key' });
    return;
  }

  var controller = new AbortController();
  var timeout = setTimeout(function () { controller.abort(); }, 20000);

  try {
    var response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + apiKey,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://emotion-diary-horimi.vercel.app',
        'X-Title': 'AI Empathy Diary'
      },
      body: JSON.stringify({
        model: 'openai/gpt-oss-20b:free',
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: text.slice(0, 1000) }
        ],
        temperature: 0.8,
        max_tokens: 300
      }),
      signal: controller.signal
    });

    clearTimeout(timeout);

    if (!response.ok) {
      var errText = await response.text();
      res.status(502).json({ error: 'openrouter_error', detail: errText.slice(0, 500) });
      return;
    }

    var data = await response.json();
    var content = data && data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content;
    if (!content) {
      res.status(502).json({ error: 'empty_response' });
      return;
    }

    var parsed = parseModelJson(content);
    if (!parsed || !parsed.emotion || !parsed.message) {
      res.status(502).json({ error: 'unparseable_response', raw: String(content).slice(0, 500) });
      return;
    }

    res.status(200).json({
      emotion: String(parsed.emotion).trim(),
      intensity: ['low', 'medium', 'high'].indexOf(parsed.intensity) !== -1 ? parsed.intensity : 'medium',
      message: String(parsed.message).trim()
    });
  } catch (err) {
    clearTimeout(timeout);
    res.status(502).json({ error: 'request_failed', detail: String((err && err.message) || err) });
  }
};
