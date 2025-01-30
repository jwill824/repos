#!/usr/bin/env python3

import sys
import subprocess
import os
import asyncio
import aiohttp
import json
from pathlib import Path

def log_debug(message):
    with open("/tmp/git-hook-debug.log", "a") as f:
        f.write(f"{message}\n")

_api_key_cache = None

def get_git_diff():
    try:
        result = subprocess.run(
            ['git', 'diff', '--cached', '--no-color', '--no-ext-diff'],
            capture_output=True,
            text=True,
            timeout=5
        )
        diff_text = result.stdout
        log_debug(f"Git diff output (first 500 chars):\n{diff_text[:500]}")
        
        if not diff_text.strip():
            log_debug("No changes found in git diff")
            return None
            
        return diff_text
    except subprocess.TimeoutExpired:
        log_debug("Error: Git diff operation timed out")
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        log_debug(f"Error getting git diff: {e}")
        sys.exit(1)

def get_cached_api_key():
    """Get API key with improved logging and git config first"""
    global _api_key_cache
    if _api_key_cache:
        return _api_key_cache
    
    # Try git config first since we know that's working
    try:
        result = subprocess.run(
            ['git', 'config', '--get', 'ai.apikey'],
            capture_output=True,
            text=True,
            timeout=2
        )
        _api_key_cache = result.stdout.strip()
        if _api_key_cache:
            log_debug("Found API key in git config")
            return _api_key_cache
    except Exception as e:
        log_debug(f"Error reading from git config: {e}")
    
    # Fall back to environment variable if git config fails
    _api_key_cache = os.getenv('ANTHROPIC_API_KEY')
    if _api_key_cache:
        log_debug("Found API key in environment variable")
        return _api_key_cache
    
    log_debug("No API key found in git config or environment")
    return None

async def get_ai_summary(diff_text, api_key):
    """Get AI-generated summary using async API call"""
    headers = {
        "Content-Type": "application/json",
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01"
    }
    
    prompt = f"Generate a concise conventional commit message (type: description) for this diff:\n{diff_text}"
    
    data = {
        "model": "claude-3-haiku-20240307",
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ],
        "max_tokens": 100,
        "temperature": 0.3,
        "top_p": 0.8
    }

    try:
        log_debug("Making API call to Anthropic...")
        async with aiohttp.ClientSession() as session:
            async with session.post(
                "https://api.anthropic.com/v1/messages",
                headers=headers,
                json=data,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                response_text = await response.text()
                
                if response.status != 200:
                    try:
                        error_json = json.loads(response_text)
                        error_message = error_json.get('error', {}).get('message', 'Unknown error')
                        
                        # Check for specific error types
                        if "credit balance is too low" in error_message:
                            print("\n⚠️  Anthropic API Error: Insufficient credits.", file=sys.stderr)
                            print("Please visit https://console.anthropic.com/settings/billing to add credits.", file=sys.stderr)
                            print("Falling back to manual commit message...\n", file=sys.stderr)
                        else:
                            print(f"\n⚠️  Anthropic API Error: {error_message}", file=sys.stderr)
                            print("Falling back to manual commit message...\n", file=sys.stderr)
                            
                    except json.JSONDecodeError:
                        print(f"\n⚠️  Anthropic API Error: {response.status}", file=sys.stderr)
                        
                    log_debug(f"API error {response.status}: {response_text}")
                    return None
                
                result = await response.json()
                message = result['content'][0]['text'].strip()
                log_debug(f"Generated message: {message}")
                return message
                
    except asyncio.TimeoutError:
        print("\n⚠️  Anthropic API request timed out. Falling back to manual commit message...\n", file=sys.stderr)
        log_debug("API request timed out")
        return None
    except Exception as e:
        print(f"\n⚠️  Error calling Anthropic API: {str(e)}", file=sys.stderr)
        print("Falling back to manual commit message...\n", file=sys.stderr)
        log_debug(f"Error calling Anthropic API: {str(e)}")
        return None

async def main():
    log_debug("\n--- Starting new commit message generation ---")
    # Get the commit message file path from git
    commit_msg_file = sys.argv[1]
    log_debug(f"Commit message file: {commit_msg_file}")
    
    # Check for existing message
    try:
        with open(commit_msg_file, 'r') as f:
            content = f.read()
            log_debug(f"Raw content:\n{content}")
            
            # Only consider non-comment lines and non-empty lines
            real_content = [
                line.strip() 
                for line in content.splitlines() 
                if line.strip() and not line.strip().startswith('#')
            ]
            
            log_debug(f"Parsed content lines: {real_content}")
            
            # If we have any non-comment, non-empty lines, treat it as an existing message
            if real_content:
                log_debug(f"Found existing message: {real_content}, exiting")
                sys.exit(0)
            else:
                log_debug("No existing message found, proceeding with AI generation")
    except Exception as e:
        log_debug(f"Error reading commit message file: {e}")
    
    # Load API key
    api_key = get_cached_api_key()
    if not api_key:
        log_debug("No API key found, exiting")
        sys.exit(0)
    
    # Get the diff
    diff_text = get_git_diff()
    if not diff_text:
        log_debug("No diff found, exiting")
        sys.exit(0)
    
    # Get AI summary
    summary = await get_ai_summary(diff_text, api_key)
    if not summary:
        log_debug("Failed to get AI summary")
        sys.exit(1)
    
    # Write the message
    try:
        with open(commit_msg_file, 'r') as f:
            existing_content = f.read()
        
        # Write the AI message at the top, followed by the existing template
        with open(commit_msg_file, 'w') as f:
            f.write(f"{summary}\n\n{existing_content}")
        log_debug("Successfully wrote AI-generated message")
    except Exception as e:
        log_debug(f"Error writing commit message: {e}")
        sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())