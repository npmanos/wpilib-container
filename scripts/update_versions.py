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

    # Universal Groovy property extractor: handles single/double quotes, unquoted variables, and aliases
    def find_groovy_var(var_names, content, default=None):
        if isinstance(var_names, str):
            var_names = [var_names]
        names_pattern = "|".join(re.escape(name) for name in var_names)
        pattern = rf"ext\.(?:{names_pattern})\s*=\s*(?:['\"]([^'\"]+)['\"]|([a-zA-Z0-9_.\-]+))"
        match = re.search(pattern, content)
        if not match:
            if default is not None:
                return default
            raise ValueError(f"Could not find any of ext.{var_names} in versions.gradle")
        return match.group(1) or match.group(2)

    # 3. Parse required variables with pre-release safety
    gcc_version = find_groovy_var('gccVersion', versions_content)
    toolchain_version = find_groovy_var('toolchainGitTag', versions_content)
    jdk_tag_raw = find_groovy_var('jdkVersion', versions_content)
    
    # Handle both 'wpilibYear' and legacy 'frcYear'
    wpilib_year_raw = find_groovy_var(['wpilibYear', 'frcYear'], versions_content)
    year_match = re.search(r'\b(20\d\d)\b', wpilib_year_raw)
    wpilib_year = year_match.group(1) if year_match else wpilib_year_raw

    # Optional: Extract pre-release tool versions if needed in .versions
    advantagescope_version = find_groovy_var('advantagescopeGitTag', versions_content, default='')
    elastic_version = find_groovy_var('elasticGitTag', versions_content, default='')
    vscode_version = find_groovy_var('vsCodeVersion', versions_content, default='')

    # 4. Normalize JDK strings
    clean_jdk_ver = re.sub(r'^jdk-', '', jdk_tag_raw)
    jdk_tag = f"jdk-{clean_jdk_ver}" if not jdk_tag_raw.startswith("jdk-") else jdk_tag_raw
    jdk_tag_encoded = jdk_tag.replace('+', '%2B')
    jdk_ver_clean = clean_jdk_ver.replace('+', '_')

    # 5. Write to .versions file
    output_lines = [
        f"VSCODE_WPILIB_VERSION={wpilib_version}",
        f"WPILIB_VERSION={wpilib_version}",
        f"WPILIB_YEAR={wpilib_year}",
        f"WPILIB_YEAR_RAW={wpilib_year_raw}",
        f"GCC_VERSION={gcc_version}",
        f"TOOLCHAIN_VERSION={toolchain_version}",
        f"JDK_TAG={jdk_tag_encoded}",
        f"JDK_TAG_CLEAN={jdk_ver_clean}",
        f"VSCODE_VERSION={vscode_version}",
        f"ADVANTAGESCOPE_VERSION={advantagescope_version}",
        f"ELASTIC_VERSION={elastic_version}"
    ]


    with open('.versions', 'w') as f:
        f.write('\n'.join(output_lines) + '\n')
    
    print("Successfully updated .versions file:")
    print('\n'.join(output_lines))

if __name__ == "__main__":
    main()
