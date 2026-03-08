import { parseAxiomPlan } from './src/lib/axiomParser';

function assertEq(name: string, actual: any, expected: any) {
    if (actual !== expected) {
        console.error(`[FAIL] ${name} | Expected: ${expected} | Actual: ${actual}`);
    } else {
        console.log(`[PASS] ${name}`);
    }
}

console.log('--- AXIOM PARSER REGRESSION TESTS ---');

// Test 1: Empty Create Intent (Empty Payload Bug)
const testEmpty = parseAxiomPlan({
    baseDir: 'C:/Users/Martin/.n8n-files/Axiom_Files',
    response: JSON.stringify({ action: 'create_empty_file', path: 'no_content.txt' }),
    originalCommand: 'create a text file and name it no_content.txt',
});
assertEq('create_empty_file resolves to write_file', testEmpty.action, 'write_file');
assertEq('create_empty_file has empty content', testEmpty.content, '');

// Test 2: Standard Write with Content
const testWrite = parseAxiomPlan({
    baseDir: 'C:/Users/Martin/.n8n-files/Axiom_Files',
    response: JSON.stringify({ action: 'write_file', path: 'has_content.txt', content: 'hello world' }),
    originalCommand: 'write hello world to has_content.txt',
});
assertEq('write_file handles content', testWrite.content, 'hello world');

// Test 3: Follow-Up Selection UI Bug (Implicit clarify resolution)
const testSelect = parseAxiomPlan({
    baseDir: 'C:/Users/Martin/.n8n-files/Axiom_Files',
    response: JSON.stringify({ action: 'clarify' }),
    originalCommand: '1', // The user clicked option 1 in the UI follow-up
});
// When action is clarify, ensure it passes through correctly instead of defaulting to error
assertEq('Clarify handles numeric option selection', testSelect.action, 'clarify');

// Test 4: Unsupported Operation Lock (Rename/Move)
const testRename = parseAxiomPlan({
    baseDir: 'C:/Users/Martin/.n8n-files/Axiom_Files',
    response: JSON.stringify({ action: 'write_file', path: 'new_name.txt' }),
    originalCommand: 'rename old.txt to new_name.txt',
});
assertEq('Rename intent intercepted and denied', testRename.action, 'clarify');

// Test 5: Delete operation mapped correctly
const testDelete = parseAxiomPlan({
    baseDir: 'C:/Users/Martin/.n8n-files/Axiom_Files',
    response: JSON.stringify({ action: 'delete_file', path: 'delete_me.txt' }),
    originalCommand: 'delete delete_me.txt',
});
assertEq('Delete action supported in schema', testDelete.action, 'delete_file');

console.log('--- DONE ---');
