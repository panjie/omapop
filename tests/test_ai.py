import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HELPER = Path(__file__).resolve().parents[1] / 'bin/omapop-ai.py'
spec = importlib.util.spec_from_file_location('omapop_ai', HELPER)
ai = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ai)


def connection(provider='deepseek', base=None):
    return dict(id='test', name='Test', provider=provider, model='test-model', baseUrl=base or ai.PRESETS[provider], maxTokens=4096)


class AiTests(unittest.TestCase):
    def test_templates_are_literal_and_multiline(self):
        text = '中文\n${command} {{text}}'
        self.assertEqual(ai.prompt_text('A {{text}} B {{text}}', text), 'A ' + text + ' B ' + text)
        self.assertEqual(ai.prompt_text('解释', text), '解释\n\n待处理文本：\n' + text)

    def test_validation_rejects_dangling_duplicate_and_insecure_connections(self):
        config = copy.deepcopy(ai.DEFAULT)
        config['connections'] = [connection()]
        config['defaultConnection'] = 'test'
        self.assertEqual(ai.validate(config)['defaultConnection'], 'test')
        for url in ['http://example.org', 'https://user:secret@example.org', 'https://example.org/?key=secret', 'file:///tmp/x']:
            with self.assertRaises(ValueError):
                ai.endpoint(url)
        config['buttons'][0]['connection'] = 'missing'
        with self.assertRaises(ValueError): ai.validate(config)
        config['buttons'][0]['connection'] = ''
        config['buttons'].append(config['buttons'][0])
        with self.assertRaises(ValueError): ai.validate(config)

    def test_provider_requests(self):
        expected = {'deepseek': '/chat/completions', 'compatible': '/chat/completions', 'openai': '/responses', 'claude': '/messages', 'gemini': ':streamGenerateContent?alt=sse'}
        for provider, suffix in expected.items():
            url, headers, body = ai.request_spec(connection(provider), 'secret', '你好\nworld')
            self.assertTrue(url.endswith(suffix))
            self.assertNotIn('secret', url)
            self.assertNotIn('secret', json.dumps(body))
            self.assertEqual('thinking' in body, provider == 'deepseek')
        _, _, body = ai.request_spec(connection('openai'), 'secret', 'hello')
        self.assertFalse(body['store'])

    def test_stream_protocols_and_truncation(self):
        cases = [('deepseek', {'choices': [{'delta': {'content': '你好\n'}, 'finish_reason': None}]}, '你好\n', False),
                 ('openai', {'type': 'response.output_text.delta', 'delta': 'Hello'}, 'Hello', False),
                 ('openai', {'type': 'response.completed'}, '', True),
                 ('claude', {'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': 'hi'}}, 'hi', False),
                 ('claude', {'type': 'message_stop'}, '', True),
                 ('gemini', {'candidates': [{'content': {'parts': [{'text': 'hidden', 'thought': True}, {'text': 'hi'}]}, 'finishReason': 'STOP'}]}, 'hi', True)]
        for provider, event, text, done in cases:
            self.assertEqual(ai.decode_event(provider, json.dumps(event)), (text, done))
        for provider, event in [('deepseek', {'choices': [{'finish_reason': 'length'}]}), ('openai', {'type': 'response.incomplete'}), ('claude', {'delta': {'stop_reason': 'max_tokens'}}), ('gemini', {'candidates': [{'finishReason': 'SAFETY'}]})]:
            with self.assertRaises(ValueError): ai.decode_event(provider, json.dumps(event))

    def test_sse_comments_crlf_multiline_and_limits(self):
        data = b': ping\r\nevent: delta\r\ndata: {"a":\r\ndata: 1}\r\n\r\ndata: [DONE]\n\n'
        self.assertEqual(list(ai.sse(io.BytesIO(data))), ['{"a":\n1}', '[DONE]'])
        with self.assertRaises(ValueError): list(ai.sse(io.BytesIO(b'x' * 65537)))

    def test_private_atomic_config_and_preserved_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            config = copy.deepcopy(ai.DEFAULT)
            config['connections'] = [connection()]
            config['defaultConnection'] = 'test'
            def save(keys):
                return subprocess.run(['python3', '-I', str(HELPER), 'save', '--config-dir', tmp], input=json.dumps({'config': config, 'keys': keys}), capture_output=True, text=True)
            first = save({'test': 'SECRET'})
            self.assertEqual(first.returncode, 0, first.stdout)
            self.assertNotIn('SECRET', first.stdout + first.stderr)
            self.assertTrue(json.loads(first.stdout)['config']['connections'][0]['hasKey'])
            self.assertEqual(save({}).returncode, 0)
            self.assertEqual(json.loads((directory / 'ai-secrets.json').read_text())['test'], 'SECRET')
            self.assertEqual(stat.S_IMODE((directory / 'ai-secrets.json').stat().st_mode), 0o600)
            self.assertNotIn('SECRET', (directory / 'ai.json').read_text())

    def test_popai_import_preserves_existing_config_and_rejects_repeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            ai.write_json(path / 'settings.json', {'options': {'io.github.panjie.popai': {'apiKey': 'SECRET', 'model': 'custom', 'buttons': '[{"title":"摘要","prompt":"总结 {{text}}"}]', 'output': 'copy-result'}}})
            config, keys = ai.migrate(path, ai.DEFAULT, {})
            self.assertEqual(len(config['buttons']), 3)
            self.assertEqual(config['buttons'][-1]['output'], 'copy')
            self.assertEqual(keys['popai'], 'SECRET')
            with self.assertRaises(ValueError): ai.migrate(path, config, keys)

    def test_http_stream_and_incomplete_disconnect(self):
        class Handler(BaseHTTPRequestHandler):
            truncated = False
            def log_message(self, *_): pass
            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                self.server.payload = payload
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()
                self.wfile.write(('data: ' + json.dumps({'choices': [{'delta': {'content': '你好\nworld'}}]}) + '\n\n').encode())
                if not self.truncated: self.wfile.write(b'data: [DONE]\n\n')
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            c = connection('compatible', f'http://127.0.0.1:{server.server_port}')
            output = io.StringIO()
            with contextlib.redirect_stdout(output): ai.generate(c, '', 'selected')
            events = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(events, [{'type': 'delta', 'text': '你好\nworld'}, {'type': 'done'}])
            self.assertEqual(server.payload['messages'][-1]['content'], 'selected')
            Handler.truncated = True
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ValueError): ai.generate(c, '', 'selected')
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__': unittest.main()
