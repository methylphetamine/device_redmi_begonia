# CI ROM build

`/.github/workflows/build-rom.yml` builds the Lunaris 16.2 ROM for the Redmi
Note 8 Pro (begonia) and uploads the resulting zip to Gofile. The ROM is too
large to rely on GitHub's artifact/release upload limits, so it is not attached
to the Actions run.

## Requirements

- An Ubuntu 24.04 runner with at least **100 GB free disk** (**150 GB
  recommended**), **12 GB RAM** (16 GB recommended), and **8+ CPU cores**.
- A full AOSP build does not fit on a standard GitHub-hosted runner. Run it on
  a self-hosted or larger runner and set the workflow's `runner_label` input.
  You can also set a repository variable named `ROM_RUNNER_LABEL` as the
  default.
- `repo`, `git-lfs`, Java 21, and the normal AOSP build packages are installed
  by the workflow.

## Gofile configuration

Gofile guest uploads work without credentials. For an account upload, add:

- **Secret** `GOFILE_TOKEN`: your Gofile API token.
- **Variable** `GOFILE_FOLDER_ID` (optional): destination folder ID. This is
  only used when `GOFILE_TOKEN` is set.

The download link is written to the workflow run summary. A small metadata
artifact containing the zip SHA256 and build log is kept for three days.

## Defaults

- ROM manifest: `https://github.com/Lunaris-AOSP/android`, branch `16.2`
- Lunch target: `lineage_begonia-bp4a-user`
- Make target: `bacon`
- Kernel: `Saikrishna1504/kernel_xiaomi_mt6785`, branch `main`
- Vendor: `Saikrishna1504/vendor_redmi_begonia`, branch `bka`

The kernel and vendor repositories can be overridden from the manual dispatch
form. Other dependencies are taken from these branches:

- `vendor/redmi/begonia-ims`: `begonia-dev/android_vendor_redmi_begonia-ims@14.0`
- `hardware/mediatek`: `LineageOS/android_hardware_mediatek@lineage-23.2`
- `hardware/xiaomi`: `LineageOS/android_hardware_xiaomi@lineage-23.2`
- `device/mediatek/sepolicy_vndr`: `LineageOS/android_device_mediatek_sepolicy_vndr@lineage-23.2`

## Running

1. Add the optional Gofile secret/variable.
2. Go to **Actions → Build Lunaris ROM (begonia) → Run workflow**.
3. Set `runner_label` to your self-hosted/larger runner label if it is not
   `ubuntu-24.04`.
4. Wait for the build to finish and use the Gofile link in the run summary.

The workflow is manual-only so a normal device-tree push does not start a
multi-hour ROM build.
