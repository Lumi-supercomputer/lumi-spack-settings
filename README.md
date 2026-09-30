# Spack configuration files for LUMI

This repository contains the configuration for the central Spack instance under `/appl/lumi/` on LUMI. It defines compilers, external packages, build cache, module-generation settings, and the Lmod modulefiles users load to activate Spack.

## What gets deployed

```
/appl/lumi/
├── lumi-spack-settings/         # ← contents of this repo
│   ├── configs/
│   │   ├── common/
│   │   ├── partition-c/
│   │   └── partition-g/
│   ├── modules/
│   │   ├── spack-cpu/<version>.lua
│   │   └── spack-gpu/<version>.lua
│   └── lib/
├── spack-<version>/             # Spack source tree (one dir per supported version)
└── spack-buildcache/            # binary build cache (filesystem mirror)
```

Lmod reaches these modulefiles through per-module directory symlinks from the LUMI module tree (`/appl/lumi/modules/SoftwareStack/spack-{cpu,gpu}` -> `/appl/lumi/lumi-spack-settings/modules/spack-{cpu,gpu}`), maintained outside this repo. `lib/spack-module.lua` reads configs from `/appl/lumi/lumi-spack-settings`, overridable with `LUMI_SPACK_SETTINGS_ROOT`.

## User-facing usage

Load one of the Spack modules (e.g. `spack-gpu/1.2`). They share the `LUMI_SoftwareStack` Lmod family, so they are mutually exclusive and also conflict with the LUMI software stack — pick one per session:

```bash
module load spack-cpu/1.2        # or spack-gpu/1.2
```

`SPACK_USER_PREFIX` controls where the user's installs and generated modules land. It defaults to `$HOME/spack-prefix` and can be set before loading the module to point elsewhere (e.g. `/scratch/<project>/<user>/spack`).

Three representative workflows on top of that:

**1. One-shot install**

```bash
spack install <pkg>
module load <pkg>           # immediately on MODULEPATH
```

**2. Environment**

An environment groups a set of specs and concretizes them together so their shared dependencies match, then installs them as a unit. Useful for building a coherent stack of related packages.

```bash
spack env create my-env
spack env activate my-env
spack add <pkg1>
spack add <pkg2>
spack concretize
spack install
```

**3. Environment with depfile (parallel build across packages)**

`spack env depfile` writes a Makefile whose targets are the environment's specs with their dependency edges, so `make -j` can build independent packages concurrently.

```bash
spack env create my-env
spack env activate my-env
spack add <pkg1>
spack add <pkg2>
spack concretize
spack env depfile -o Makefile
make -j 16
```

## Repo layout

```
configs/
  common/
    config.yaml         install tree, caches, build_jobs
    mirrors.yaml        build cache mirror
    modules.yaml        Lmod generation (flat layout — see "Adding a compiler")
    concretizer.yaml    host_compatible: false (Zen3 builds on Zen2 login nodes)
    packages.yaml       shared compilers (gcc, cce) + slurm + default prefer/require/providers
  partition-c/
    packages.yaml       libfabric (plain)
  partition-g/
    packages.yaml       GPU defaults (require), libfabric +rocm, mpich/openmpi +rocm, llvm-amdgpu, ROCm/HIP stack
lib/
  spack-module.lua      the actual modulefile — partition derived at runtime
modules/
  spack-cpu/<ver>.lua   symlink → ../../lib/spack-module.lua
  spack-gpu/<ver>.lua   symlink → ../../lib/spack-module.lua
```

## Maintenance tasks

### Adding a compiler (e.g., new CPE rolls out gcc 15 or cce 21)

This requires edits in **two** files. There is no automation, by design.

1. **Add the external in `configs/common/packages.yaml`** under the appropriate compiler key (`gcc`, `cce`, etc.). Include `extra_attributes.compilers` with the c/cxx/fortran paths. (For a GPU-only compiler like `llvm-amdgpu`, add it to `configs/partition-g/packages.yaml` instead.)
2. **Add the same compiler spec to `configs/common/modules.yaml` under `core_compilers:`**. If you skip this step, modules built with the new compiler will land in `<compiler>/<version>/` instead of `Core/`, breaking the one-shot `module load` UX.
3. If it should become the new default compiler, update the `prefer:` entries under `packages:c:`, `packages:cxx:` and `packages:fortran:` in `configs/common/packages.yaml` to point at the new version.

The `core_compilers` list silently ignores compilers that aren't installed, so listing the GPU compiler in the common modules.yaml is harmless on the CPU partition.

### Removing a compiler (decommissioning an old CPE)

Reverse of above:

1. Remove the external block from `configs/common/packages.yaml` (or `configs/partition-g/packages.yaml` for `llvm-amdgpu`).
2. Remove the spec from `configs/common/modules.yaml` core_compilers (optional — leaving a dead entry is harmless, but keep the list tidy).
3. If it was the default compiler (the `prefer:` entries under `packages:c:`, `packages:cxx:` and `packages:fortran:` in `configs/common/packages.yaml`), point them at a still-installed version.

### Adding a ROCm package (GPU partition)

Add the external in `configs/partition-g/packages.yaml` only, under the package key, with `buildable: false` and `prefix: /opt/rocm-X.Y.Z`. ROCm version is currently 6.3.4 throughout.

### Bumping the Spack version

All edits happen in the testing area, `/appl/lumi/` on uan06 (see [Deployment](#deployment)), and are picked up by the next deploy run. Production `/appl/lumi/` is never touched directly.

1. On uan06, clone the new Spack release branch as a sibling of `lumi-spack-settings/`. Shallow clone keeps history and tags out:

   ```bash
   umask 002
   cd /appl/lumi
   git clone --depth 1 --branch releases/v<new> \
       https://github.com/spack/spack.git spack-<new>
   ```

   A release branch (e.g. `releases/v1.2`) tracks every patch release for that minor version, so future patch updates are `git -C /appl/lumi/spack-<new> pull` on uan06 followed by another deploy — no re-clone, no module rename.

2. In the uan06 copy of this repo, add the modulefile symlinks under both partitions:

   ```bash
   cd /appl/lumi/lumi-spack-settings
   ln -s ../../lib/spack-module.lua modules/spack-cpu/<new>.lua
   ln -s ../../lib/spack-module.lua modules/spack-gpu/<new>.lua
   ```

   The file name is what Lmod parses as the module version; the symlink target is always the same shared implementation.

3. Verify the new version concretizes against the existing configs. Minor/patch bumps generally do; major bumps may require config schema migrations.

4. Run the deploy script (see [Deployment](#deployment)).

5. Decommissioning an old version: on uan06, delete its `.lua` modulefiles and remove the `spack-<old>/` clone, then deploy. The deploy script doesn't touch siblings absent from the testing area, so `rm -rf /pfs/lustrep[1-4]/appl/lumi/spack-<old>` is a separate manual step.

### Pushing to the build cache

Only the support team pushes. After installing packages worth caching (e.g., common heavy dependencies):

```bash
spack buildcache push --unsigned /appl/lumi/spack-buildcache <spec>
```

Single cache for both partitions — hash-based matching prevents cross-architecture misuse. No GPG signing; trust is via filesystem permissions on `/appl/lumi/spack-buildcache/`.

### Default compiler / variants

- Default compiler: set via `prefer: [gcc@X.Y.Z]` on the `c`, `cxx` and `fortran` virtuals in `configs/common/packages.yaml`. Soft preference — users can override with `%cce` or `%llvm-amdgpu` per spec.
- Default variants: hard `packages:all:require:` in the relevant partition file. The GPU partition currently has `[target=zen3, '+rocm amdgpu_target=gfx90a']` in `configs/partition-g/packages.yaml`. Soft `variants:` and `prefer:` don't override package defaults reliably in 1.1.
- Provider preferences: `packages:all:providers:` in `configs/common/packages.yaml` (currently `blas: [openblas]`, `lapack: [openblas]`, `mpi: [mpich, openmpi]`).

## Deployment

Two-step workflow: set up and test on uan06, then run the deploy script. On uan06 (TDS) `/appl/lumi` is a test filesystem, not production, so the trees are tested at the same paths they are deployed to.

1. **Set up.** On uan06, clone this repo and the Spack source tree side by side under `/appl/lumi`. `umask 002` matters (see [Permissions](#permissions)) — `rsync -a` preserves source perms, so the tested tree must already be group-readable:

   ```bash
   umask 002
   cd /appl/lumi
   git clone https://github.com/Lumi-supercomputer/lumi-spack-settings.git
   git clone --depth 1 --branch releases/v1.2 \
       https://github.com/spack/spack.git spack-1.2
   ```

   Multiple `spack-<ver>/` clones can coexist when several Spack versions are supported in parallel.

2. **Deploy.** On uan06, run the script from the tested repo:

   ```bash
   /appl/lumi/lumi-spack-settings/deployment/sync_to_appl_lumi.sh
   ```

   It auto-discovers `lumi-spack-settings/` and any `spack-[0-9]*/` siblings under `/appl/lumi`, refuses to run where `/appl/lumi` is production itself (any node but uan06), previews the deletion impact against lustrep1, prompts for confirmation, then rsyncs in parallel to all four `/pfs/lustrep[1-4]/appl/lumi/` with `--delete`. Symlink targets are checked post-sync. Logs land in `~/appl_sync_logs/`.

   `spack-buildcache/` is not in scope — see [Pushing to the build cache](#pushing-to-the-build-cache).

Patch updates: `git -C /appl/lumi/spack-1.2 pull` on uan06, then re-run the deploy script.

### Permissions

`/appl/lumi/lumi-spack-settings/` and `/appl/lumi/spack-<ver>/` are owned by the Spack support group; members push updates, end users only read. LUMI's default personal umask is 077 (files 600, dirs 700) — clone or rsync with that and end users can neither read nor traverse the tree, so `module load spack-cpu/<ver>` fails on `setup-env.sh` and `bin/spack`.

Set `umask 002` in the deploying shell before any `git clone` or other write into `/appl/lumi/`. That yields files 664 and dirs 775 — group writes, world reads and traverses. The deploy script also sets `umask 002` internally as a backstop. `rsync -a` preserves source perms, so getting it right on uan06 is what propagates to the destinations.

For first-time setup of each destination, chgrp to the support group and setgid the directories so subsequent rsyncs and direct writes inherit the group regardless of the depositor's primary group:

```bash
for d in /pfs/lustrep{1,2,3,4}/appl/lumi/lumi-spack-settings /pfs/lustrep{1,2,3,4}/appl/lumi/spack-<ver>; do
    chgrp -R <support-group> "$d"
    find "$d" -type d -exec chmod g+s {} +
done
```

### Verifying the deploy

Run through the usage examples above with `SPACK_USER_PREFIX` pointed at a scratch location (e.g. `/scratch/<project>/<user>/spack-test`) to confirm the deploy is healthy.

To test before deploying, use uan06 (TDS): there `/appl/lumi` is a test filesystem, not production, so a checkout at `/appl/lumi/lumi-spack-settings` is exercised at its deployed path with the plain `module load`.

To test a checkout in a different location, point both roots at it:

```bash
export LUMI_SPACK_SETTINGS_ROOT=/scratch/<project>/<user>/lumi-spack-settings
module use $LUMI_SPACK_SETTINGS_ROOT/modules
module load spack-gpu/<ver>
```

## Verifying configuration

Useful commands when debugging:

```bash
spack config get packages       # merged effective packages config
spack config get modules        # merged effective modules config
spack config blame modules      # which file each setting comes from
spack spec -I <pkg>             # see what concretization picks
spack arch                      # node arch (zen2 on UAN, zen3 on compute)
```

If a setting isn't taking effect, `spack config blame` is almost always the fastest way to find what's overriding it (a stale `spack.yaml` in an active environment is a common culprit — environment scope wins over system scope).
