import re

files = [
    'src/sage/core/smp_json.sage',
    'src/sage/server/orangepi_relay.sage',
    'src/sage/client/rpi2_client.sage',
    'src/sage/client/rpi4_client.sage',
    'src/sage/client/smp_client.sage'
]

out = "import sys\nimport tcp\nimport thread\nimport io\n\nproc substring(s, start, length):\n    let res = \"\"\n    for i in range(length):\n        if start + i < len(s):\n            res = res + s[start + i]\n        end\n    end\n    return res\n\n"

for f in files:
    with open(f, 'r') as fd:
        content = fd.read()
    
    # Remove imports
    content = re.sub(r'^import .*\n', '', content, flags=re.MULTILINE)
    content = content.replace('gc_disable()\n', '')
    content = content.replace('smp_json.json_encode', 'json_encode')
    content = content.replace('smp_json.json_decode', 'json_decode')
    
    funcs = ['read_sys_file', 'stripnl', 'get_cpu_temp', 'get_cpu_load', 'get_memory_info', 'parse_mem_line', 'get_dynamic_telemetry', 'send_heartbeat']
    
    # Rename main
    if 'orangepi' in f:
        # Move global parsing inside main
        content = content.replace('let argv = sys.args()\nlet RELAY_PORT = 42000\nif len(argv) >= 3:\n    RELAY_PORT = tonumber(argv[2])\nend\n', 'let RELAY_PORT = 42000\n')
        content = content.replace('proc main():', 'proc run_orangepi(mode_idx):\n    let argv = sys.args()\n    if len(argv) >= mode_idx + 2:\n        RELAY_PORT = tonumber(argv[mode_idx + 1])\n    end')
        content = content.replace('main()\n', '')
    elif 'rpi2' in f:
        # Move global parsing inside main
        content = content.replace('let argv = sys.args()\nlet ORANGEPI_HOST = "192.168.254.44"\nif len(argv) >= 3:\n    ORANGEPI_HOST = argv[2]\nend\nlet ORANGEPI_PORT = 42000\nif len(argv) >= 4:\n    ORANGEPI_PORT = tonumber(argv[3])\nend\n', 'let ORANGEPI_HOST = "192.168.254.44"\nlet ORANGEPI_PORT = 42000\n')
        content = content.replace('proc main():', 'proc run_rpi2(mode_idx):\n    let argv = sys.args()\n    if len(argv) >= mode_idx + 2:\n        ORANGEPI_HOST = argv[mode_idx + 1]\n    end\n    if len(argv) >= mode_idx + 3:\n        ORANGEPI_PORT = tonumber(argv[mode_idx + 2])\n    end')
        content = content.replace('main()\n', '')
        for fn in funcs:
            content = re.sub(rf'\b{fn}\b', f'rpi2_{fn}', content)
    elif 'rpi4' in f:
        # Move global parsing inside main
        content = content.replace('let argv = sys.args()\nlet ORANGEPI_HOST = "192.168.254.44"\nif len(argv) >= 3:\n    ORANGEPI_HOST = argv[2]\nend\nlet ORANGEPI_PORT = 42000\nif len(argv) >= 4:\n    ORANGEPI_PORT = tonumber(argv[3])\nend\n', 'let ORANGEPI_HOST = "192.168.254.44"\nlet ORANGEPI_PORT = 42000\n')
        content = content.replace('proc main():', 'proc run_rpi4(mode_idx):\n    let argv = sys.args()\n    if len(argv) >= mode_idx + 2:\n        ORANGEPI_HOST = argv[mode_idx + 1]\n    end\n    if len(argv) >= mode_idx + 3:\n        ORANGEPI_PORT = tonumber(argv[mode_idx + 2])\n    end')
        content = content.replace('main()\n', '')
        for fn in funcs:
            content = re.sub(rf'\b{fn}\b', f'rpi4_{fn}', content)
    elif 'smp_client' in f:
        content = content.replace('parse_args()\n\n# if _start_as_router:', '')
        content = content.replace('# parse_args()\n\n# if _start_as_router:\n#     run_router_shell()\n# else:\n#     run_client_shell()', '')
        content = content.replace('# parse_args()', '') # fallback
        content = content.replace('proc parse_args():', 'proc parse_args(mode_idx):')
        content = content.replace('let i = 1\n    while i < len(argv):', 'let i = mode_idx + 1\n    while i < len(argv):')
        
    out += "\n# =========================================\n"
    out += f"# {f}\n"
    out += "# =========================================\n"
    out += content

out += """
proc main():
    let argv = sys.args()
    let mode_idx = -1
    for i in range(len(argv)):
        let arg = argv[i]
        if arg != "sage" and arg != "--jit" and arg != "--compile" and not ends_with(arg, ".sage") and not ends_with(arg, "sagesmp"):
            mode_idx = i
            break
        end
    end
    
    if mode_idx == -1:
        print("Usage: sagesmp <relay|pi2|pi4|shell> [args...]")
        return
    end
    
    let mode = argv[mode_idx]
    
    if mode == "relay":
        run_orangepi(mode_idx)
    elif mode == "pi2":
        run_rpi2(mode_idx)
    elif mode == "pi4":
        run_rpi4(mode_idx)
    elif mode == "shell":
        parse_args(mode_idx)
        if _start_as_router:
            run_router_shell()
        else:
            run_client_shell()
    else:
        print("Unknown mode: " + mode)
    end
end

proc ends_with(s, suffix):
    if len(s) < len(suffix): return false end
    return substring(s, len(s) - len(suffix), len(suffix)) == suffix
end

main()
"""

with open('src/sage/sagesmp.sage', 'w') as fd:
    fd.write(out)
