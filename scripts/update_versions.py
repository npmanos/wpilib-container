import urllib.request
import re
import os

def get_content(url):
    with urllib.request.urlopen(url) as response:
        return response.read().decode('utf-8')

def main():
    print("Fetching WPILib version...")
    # 1. Fetch gradle.properties to get the main WPILib version
    props_url = 'https://raw.githubusercontent.com/wpilibsuite/WPILibInstaller-Avalonia/refs/heads/main/gradle.properties'
    props_content = get_content(props_url)
    
    # Parse gradleRioVersion: 2026.2.1 (Handles : or = separators)
    # This maps to VSCODE_WPILIB_VERSION in the Dockerfile
    wpilib_version_match = re.search(
        r'gradleRioVersion\s*[:=]\s*["\']?([\d\.]+(?:-[\w.\-+]+)?)["\']?',
        props_content
    )
    if not wpilib_version_match:
        raise ValueError("Could not find gradleRioVersion in gradle.properties")
    wpilib_version = wpilib_version_match.group(1)
    print(f"Detected WPILib Version: {wpilib_version}")

    # 2. Fetch versions.gradle using the tag
    print(f"Fetching versions.gradle for tag v{wpilib_version}...")
    versions_url = f'https://raw.githubusercontent.com/wpilibsuite/WPILibInstaller-Avalonia/refs/tags/v{wpilib_version}/scripts/versions.gradle'
    versions_content = get_content(versions_url)

    # Helper regex for Groovy properties: ext.name = 'value' or "value"
    def find_groovy_var(var_name, content):
        pattern = f"ext\.{var_name}\s*=\s*['\"]([^'\"]+)['\"]"
        match = re.search(pattern, content)
        if not match:
            raise ValueError(f"Could not find ext.{var_name} in versions.gradle")
        return match.group(1)

    # 3. Parse required variables
    gcc_version = find_groovy_var('gccVersion', versions_content)
    toolchain_version = find_groovy_var('toolchainGitTag', versions_content)
    jdk_tag_raw = find_groovy_var('jdkVersion', versions_content) # e.g., jdk-17.0.12+7
    wpilib_year = find_groovy_var('frcYear', versions_content)

    # 4. Process variables for Dockerfile compatibility

    # JDK TAG: URL encode the '+' to '%2B' for the download URL
    # e.g., jdk-17.0.12+7 -> jdk-17.0.12%2B7
    jdk_tag_encoded = jdk_tag_raw.replace('+', '%2B')

    # JDK FILE: Construct the tar.gz filename
    # Pattern: jdk-17.0.12+7 -> OpenJDK17U-jdk_x64_linux_hotspot_17.0.12_7.tar.gz
    # Remove 'jdk-' prefix and replace '+' with '_'
    jdk_ver_clean = jdk_tag_raw.replace('jdk-', '').replace('+', '_')
    # jdk_file = f"OpenJDK17U-jdk_x64_linux_hotspot_{jdk_ver_clean}.tar.gz"

    # TOOLCHAIN FILE: Construct the filename
    # Pattern: cortexa9_vfpv3-roborio-academic-{YEAR}-x86_64-linux-gnu-Toolchain-{GCC}.tgz
    # toolchain_file = f"cortexa9_vfpv3-roborio-academic-{wpilib_year}-x86_64-linux-gnu-Toolchain-{gcc_version}.tgz"

    # 5. Write to .versions file
    output_lines = [
        f"VSCODE_WPILIB_VERSION={wpilib_version}",
        f"WPILIB_VERSION={wpilib_version}",
        f"WPILIB_YEAR={wpilib_year}",
        f"GCC_VERSION={gcc_version}",
        f"TOOLCHAIN_VERSION={toolchain_version}",
        # f"TOOLCHAIN_FILE={toolchain_file}",
        f"JDK_TAG={jdk_tag_encoded}",
        f"JDK_TAG_CLEAN={jdk_ver_clean}"
    ]

    with open('.versions', 'w') as f:
        f.write('\n'.join(output_lines) + '\n')
    
    print("Successfully updated .versions file:")
    print('\n'.join(output_lines))

if __name__ == "__main__":
    main()
