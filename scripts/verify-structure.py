import os
import sys

# ANSI colors
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
RESET = "\033[0m"

print("============================================================")
print(f"{CYAN}  UnityExpress – Project Structure Verification Tool{RESET}")
print("============================================================")

# ------------------------------------------------------------
# PROJECT ROOT DETECTION (WORKS ANYWHERE)
# ------------------------------------------------------------

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))

# If running from /scripts → go one directory up
if CURRENT_DIR.endswith("scripts"):
    PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, ".."))
else:
    # Otherwise assume user is already in root or calling script from elsewhere
    # We search upward until we find key folders
    candidate = CURRENT_DIR
    FOUND = False

    while True:
        if (
            os.path.isdir(os.path.join(candidate, "api-server")) and
            os.path.isdir(os.path.join(candidate, "charts")) and
            os.path.isdir(os.path.join(candidate, "scripts"))
        ):
            FOUND = True
            PROJECT_ROOT = candidate
            break

        parent = os.path.abspath(os.path.join(candidate, ".."))
        if parent == candidate:
            break  # Reached filesystem root
        candidate = parent

    if not FOUND:
        print(f"{RED}[ERROR] Could not locate UnityExpress project root automatically.{RESET}")
        print("Run this script from inside the UnityExpress folder or its scripts folder.")
        sys.exit(1)

print(f"[*] Project root detected as: {PROJECT_ROOT}")

# ------------------------------------------------------------
# EXPECTED STRUCTURE
# ------------------------------------------------------------
EXPECTED_STRUCTURE = {
    "api-server": [
        "Dockerfile",
        "package.json",
        "src/index.js",
        "src/config.js",
        "src/mongo.js",
        "src/kafka.js",
        "src/metrics.js",
        "src/routes.js",
    ],
    "web-server": [
        "Dockerfile",
        "nginx.conf",
        "public/index.html",
        "public/app.js",
        "public/style.css"
    ],
    "charts/unityexpress": [
        "Chart.yaml",
        "values.yaml",
        "templates/api-deployment.yaml",
        "templates/web-deployment.yaml",
        "templates/mongo-statefulset.yaml",
        "templates/kafka-deployment.yaml",
        "templates/api-hpa.yaml",
        "templates/api-servicemonitor.yaml",
        "templates/prometheus-adapter-config.yaml",
        "templates/_helpers.tpl"
    ],
    "monitoring": [
        "prometheus-adapter-values.yaml"
    ],
    "scripts": [
        "prerequisites.sh",
        "install-monitoring.sh",
        "build-images.sh",
        "deploy.sh",
        "verify.sh",
    ]
}

# ------------------------------------------------------------
# STRUCTURE VERIFICATION
# ------------------------------------------------------------

missing_items = []

def check_structure():
    print("\nChecking project structure...\n")

    for folder, expected_files in EXPECTED_STRUCTURE.items():
        folder_path = os.path.join(PROJECT_ROOT, folder)

        if not os.path.isdir(folder_path):
            print(f"{RED}[MISSING FOLDER]{RESET} {folder_path}")
            missing_items.append(folder_path)
            continue

        print(f"{GREEN}[OK] Folder exists:{RESET} {folder}")

        # Check required files inside the folder
        for rel_file in expected_files:
            file_path = os.path.join(folder_path, rel_file)

            if os.path.isfile(file_path):
                print(f"   {GREEN}[OK]{RESET} {rel_file}")
            else:
                print(f"   {RED}[MISSING FILE]{RESET} {rel_file}")
                missing_items.append(file_path)

    print("\n============================================================")
    if missing_items:
        print(f"{RED}  Structure verification FAILED.{RESET}")
        print("  Missing components:")
        for item in missing_items:
            print(f"   - {item}")

        print("\nFix the missing folders/files before continuing.")
        print("============================================================")
        sys.exit(1)
    else:
        print(f"{GREEN}  Structure verification PASSED.{RESET}")
        print("  All required files & folders are present.")
        print("============================================================")

# ------------------------------------------------------------
# Run check
# ------------------------------------------------------------
if __name__ == "__main__":
    check_structure()
