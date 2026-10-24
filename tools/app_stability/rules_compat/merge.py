"""Pure, reversible append of archive namespaces; never deploy or read records."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MARKER = 'DEDA_STABILITY_ARCHIVE_REVIEW_ONLY_V1'
NAMESPACES = ('deda_progress_evidence', 'deda_progress_receipts',
              'deda_progress_migrations', 'deda_verified_progress')
RENAMES = {'ownsProgressAccount': 'dedaArchiveAccountOwnerV1',
           'validLegacyText': 'dedaArchiveLegacyTextV1',
           'validEvidence': 'dedaArchiveEvidenceV1'}


class GuardError(Exception):
    """Static reason code only; never include private policy or credentials."""


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def code_mask(source):
    """Keep offsets/newlines while masking quoted text and comments."""
    out = list(source)
    i = 0
    while i < len(source):
        end = i
        if source.startswith('//', i):
            end = source.find('\n', i)
            if end < 0:
                end = len(source)
        elif source.startswith('/*', i):
            close = source.find('*/', i + 2)
            if close < 0:
                raise GuardError('unterminated-comment')
            end = close + 2
        elif source[i] in "\"'":
            quote = source[i]
            end = i + 1
            while end < len(source):
                if source[end] == '\\':
                    end += 2
                elif source[end] == quote:
                    end += 1
                    break
                else:
                    end += 1
            else:
                raise GuardError('unterminated-string')
        if end > i:
            for index in range(i, min(end, len(source))):
                if source[index] not in '\r\n':
                    out[index] = ' '
            i = end
        else:
            i += 1
    return ''.join(out)


def block_end(mask, opening):
    if opening >= len(mask) or mask[opening] != '{':
        raise GuardError('missing-block-opening')
    depth = 0
    for index in range(opening, len(mask)):
        if mask[index] == '{':
            depth += 1
        elif mask[index] == '}':
            depth -= 1
            if depth == 0:
                return index
    raise GuardError('unclosed-block')


def match_headers(mask):
    """Read path headers, including variable braces and compact formatting."""
    result = []
    for token in re.finditer(r'\bmatch\s*(?=/)', mask):
        start = token.end()
        index, variable = start, False
        while index < len(mask):
            char = mask[index]
            if variable:
                if char == '}':
                    variable = False
            elif char == '{' and index > start and mask[index - 1] == '/':
                variable = True
            elif char == '{':
                path = re.sub(r'\s+', '', mask[start:index])
                result.append((token.start(), path, index, block_end(mask, index)))
                break
            index += 1
        else:
            raise GuardError('unreadable-match-header')
    return result


def extension(candidate):
    start = candidate.find('    function ownsProgressAccount(accountKey) {')
    end = candidate.find('    match /deda_sessions/{uid} {')
    if start < 0 or end <= start:
        raise GuardError('unexpected-archive-candidate')
    text = candidate[start:end]
    mask = code_mask(text)
    replacements = []
    for name, renamed in RENAMES.items():
        if len(re.findall(r'\bfunction\s+' + name + r'\s*\(', mask)) != 1:
            raise GuardError('archive-helper-count')
        replacements += [(match.start(), match.end(), renamed)
                         for match in re.finditer(r'\b' + name + r'\b', mask)]
    for start, end, value in sorted(replacements, reverse=True):
        text = text[:start] + value + text[end:]
    scoped = code_mask(text)
    for namespace in NAMESPACES:
        if len(re.findall(r'\bmatch\s*/' + namespace + r'\b', scoped)) != 1:
            raise GuardError('archive-namespace-count')
    if re.search(r'\bmatch\s*/(?:users|deda_sessions)\b', scoped):
        raise GuardError('legacy-user-or-session-policy-in-extension')
    expected = {
        '/deda_progress_evidence/{accountKey}/captures/{captureId}',
        '/deda_progress_receipts/{accountKey}/events/{eventId}',
        '/deda_progress_migrations/{accountKey}/{document=**}',
        '/deda_verified_progress/{accountKey}',
    }
    top = set()
    for match in re.finditer(r'\bmatch\s+(/[^\s]+)\s+\{', scoped):
        prefix = scoped[:match.start()]
        depth = prefix.count('{') - prefix.count('}')
        if depth == 0:
            top.add(match[1])
        elif depth != 1 or match[1] != '/events/{eventId}':
            raise GuardError('unexpected-extension-path')
    if top != expected:
        raise GuardError('extension-top-level-scope-changed')
    return '\n    // ' + MARKER + '\n' + text + '    // END_' + MARKER + '\n'


def merge(active, candidate):
    if not re.match(r"\s*rules_version\s*=\s*['\"]2['\"]\s*;", active.lstrip('\ufeff')):
        raise GuardError('unsupported-rules-version')
    if MARKER in active:
        raise GuardError('extension-already-present')
    mask = code_mask(active)
    services = list(re.finditer(r'\bservice\s+cloud\.firestore\s*\{', mask))
    roots = list(re.finditer(r'\bmatch\s*/databases/\{database\}/documents\s*\{', mask))
    if len(services) != 1 or len(roots) != 1:
        raise GuardError('one-firestore-documents-root-required')
    service_end = block_end(mask, services[0].end() - 1)
    root = roots[0]
    close = block_end(mask, root.end() - 1)
    if not services[0].end() <= root.start() < close < service_end:
        raise GuardError('documents-root-not-in-firestore-service')
    # Validate the entire brace structure, including text after the selected
    # root; a malformed source must not be transformed by guessing.
    balance = 0
    for char in mask:
        balance += (char == '{') - (char == '}')
        if balance < 0:
            raise GuardError('unbalanced-rules')
    if balance:
        raise GuardError('unbalanced-rules')
    headers = match_headers(mask)
    for position, path, opening, ending in headers:
        if root.end() <= position < close:
            # A fixed outer namespace cannot match the new root collections.
            containers = [item for item in headers if root.end() <= item[0] < position < item[3]]
            outer = min(containers, key=lambda item: item[0])[1] if containers else path
            first = outer.lstrip('/').split('/')[0]
            if not first.startswith('{') and first not in NAMESPACES:
                continue
            allows = re.findall(r'\ballow\b[^:;]*:\s*if\s+([^;]+);', mask[opening:ending])
            if any(value.strip() != 'false' for value in allows):
                raise GuardError('wildcard-allow-overlaps-private-namespaces')
    for name in RENAMES.values():
        if re.search(r'\b' + name + r'\b', mask):
            raise GuardError('extension-identifier-collision')
    for namespace in NAMESPACES:
        if re.search(r'\bmatch\s*/' + namespace + r'\b', mask):
            raise GuardError('namespace-already-defined')
    inserted = extension(candidate)
    result = active[:close] + inserted + active[close:]
    if result[:close] + result[close + len(inserted):] != active:
        raise GuardError('original-policy-not-byte-exact')
    if len(result.encode('utf-8')) > 256 * 1024:
        raise GuardError('candidate-exceeds-source-limit')
    return result, {'originalSHA256': digest(active), 'candidateSHA256': digest(result),
                    'extensionSHA256': digest(inserted), 'preservedByteExact': True,
                    'insertAtUnicodeOffset': close, 'insertedUnicodeLength': len(inserted),
                    'namespaces': list(NAMESPACES)}
