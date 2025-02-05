# This file adds functions to build the Newlib C library
# Copyright 2009 DoréDevelopment
# Licensed under the GPL v2. See COPYING in the root of this package
#
# Edited by Martin Lund <mgl@doredevelopment.dk>
#

newlib_start_files()
{
    CT_DoStep INFO "Installing C library headers & start files"
    CT_DoExecLog ALL cp -a "${CT_SRC_DIR}/newlib/newlib/libc/include/." \
    "${CT_HEADERS_DIR}"
    if [ "${CT_ARCH_XTENSA}" = "y" ]; then
        CT_DoLog EXTRA "Installing Xtensa headers"
        CT_DoExecLog ALL cp -r "${CT_SRC_DIR}/newlib/newlib/libc/sys/xtensa/include/."   \
                               "${CT_HEADERS_DIR}"
    fi
    CT_EndStep
}

newlib_main()
{
    # It is important to build a auxiliary library before a main one
    # because the auxiliary library creates and replace the libc.a (which it is renamed to different name later)
    if [ "${CT_LIBC_NEWLIB_AUX_BUILD}" = "y" ]; then
        newlib_AUX_BUILD
    fi

    local -a newlib_opts
    local cflags_for_target

    CT_DoStep INFO "Installing C library"

    CT_mkdir_pushd "${CT_BUILD_DIR}/build-libc"

    CT_DoLog EXTRA "Configuring C library"

    # Multilib is the default, so if it is not enabled, disable it.
    if [ "${CT_MULTILIB}" != "y" ]; then
        newlib_opts+=("--disable-multilib")
    fi

    if [ "${CT_LIBC_NEWLIB_IO_FLOAT}" = "y" ]; then
        newlib_opts+=( "--enable-newlib-io-float" )
        if [ "${CT_LIBC_NEWLIB_IO_LDBL}" = "y" ]; then
            newlib_opts+=( "--enable-newlib-io-long-double" )
        else
            newlib_opts+=( "--disable-newlib-io-long-double" )
        fi
    else
        newlib_opts+=( "--disable-newlib-io-float" )
        newlib_opts+=( "--disable-newlib-io-long-double" )
    fi

    if [ "${CT_LIBC_NEWLIB_DISABLE_SUPPLIED_SYSCALLS}" = "y" ]; then
        newlib_opts+=( "--disable-newlib-supplied-syscalls" )
    else
        newlib_opts+=( "--enable-newlib-supplied-syscalls" )
    fi

    yn_args="IO_POS_ARGS:newlib-io-pos-args
IO_C99FMT:newlib-io-c99-formats
IO_LL:newlib-io-long-long
REGISTER_FINI:newlib-register-fini
NANO_MALLOC:newlib-nano-malloc
NANO_FORMATTED_IO:newlib-nano-formatted-io
ATEXIT_DYNAMIC_ALLOC:newlib-atexit-dynamic-alloc
GLOBAL_ATEXIT:newlib-global-atexit
LITE_EXIT:lite-exit
REENT_SMALL:newlib-reent-small
MULTITHREAD:newlib-multithread
RETARGETABLE_LOCKING:newlib-retargetable-locking
WIDE_ORIENT:newlib-wide-orient
FSEEK_OPTIMIZATION:newlib-fseek-optimization
FVWRITE_IN_STREAMIO:newlib-fvwrite-in-streamio
UNBUF_STREAM_OPT:newlib-unbuf-stream-opt
ENABLE_TARGET_OPTSPACE:target-optspace
    "

    for ynarg in $yn_args; do
        var="CT_LIBC_NEWLIB_${ynarg%:*}"
        eval var=\$${var}
        argument=${ynarg#*:}


        if [ "${var}" = "y" ]; then
            newlib_opts+=( "--enable-$argument" )
        else
            newlib_opts+=( "--disable-$argument" )
        fi
    done

    [ "${CT_LIBC_NEWLIB_EXTRA_SECTIONS}" = "y" ] && \
        CT_LIBC_NEWLIB_TARGET_CFLAGS="${CT_LIBC_NEWLIB_TARGET_CFLAGS} -ffunction-sections -fdata-sections"

    [ "${CT_LIBC_NEWLIB_LTO}" = "y" ] && \
        CT_LIBC_NEWLIB_TARGET_CFLAGS="${CT_LIBC_NEWLIB_TARGET_CFLAGS} -flto"

    cflags_for_target="${CT_ALL_TARGET_CFLAGS} ${CT_LIBC_NEWLIB_TARGET_CFLAGS}"

    # Note: newlib handles the build/host/target a little bit differently
    # than one would expect:
    #   build  : not used
    #   host   : the machine building newlib
    #   target : the machine newlib runs on
    CT_DoExecLog CFG                                               \
    CC_FOR_BUILD="${CT_BUILD}-gcc"                                 \
    CFLAGS_FOR_TARGET="${cflags_for_target}"                       \
    AR_FOR_TARGET="`which ${CT_TARGET}-gcc-ar`"                    \
    RANLIB_FOR_TARGET="`which ${CT_TARGET}-gcc-ranlib`"            \
    ${CONFIG_SHELL}                                                \
    "${CT_SRC_DIR}/newlib/configure"                               \
        --host=${CT_BUILD}                                         \
        --target=${CT_TARGET}                                      \
        --prefix=${CT_PREFIX_DIR}                                  \
        "${newlib_opts[@]}"                                        \
        "${CT_LIBC_NEWLIB_EXTRA_CONFIG_ARRAY[@]}"

    CT_DoLog EXTRA "Building C library"
    CT_DoExecLog ALL make ${CT_JOBSFLAGS}

    CT_DoLog EXTRA "Installing C library"
    CT_DoExecLog ALL make install

    if [ "${CT_BUILD_MANUALS}" = "y" ]; then
        local -a doc_dir="${CT_BUILD_DIR}/build-libc/${CT_TARGET}"

        CT_DoLog EXTRA "Building and installing the C library manual"
        CT_DoExecLog ALL make pdf html

        # NEWLIB install-{pdf.html} fail for some versions
        CT_DoExecLog ALL mkdir -p "${CT_PREFIX_DIR}/share/doc/newlib"
        CT_DoExecLog ALL cp -av "${doc_dir}/newlib/libc/libc.pdf"   \
                                "${doc_dir}/newlib/libm/libm.pdf"   \
                                "${doc_dir}/newlib/libc/libc.html"  \
                                "${doc_dir}/newlib/libm/libm.html"  \
                                "${CT_PREFIX_DIR}/share/doc/newlib"
    fi

    CT_Popd
    CT_EndStep
}

newlib_AUX_BUILD() {
    local aux_name
    local aux_cflags

    aux_name="${CT_LIBC_NEWLIB_AUX_BUILD_NAME}"

    CT_DoStep INFO "Installing auxiliary ${aux_name} C library"

    mkdir -p "${CT_BUILD_DIR}/build-libc-${aux_name}"
    cd "${CT_BUILD_DIR}/build-libc-${aux_name}"

    CT_DoLog EXTRA "Configuring auxiliary ${aux_name} C library"

    # Also the same for TARGET_CFLAGS
    aux_cflags="${CT_TARGET_CFLAGS} ${CT_LIBC_NEWLIB_AUX_BUILD_TARGET_CFLAGS}"

    CT_DoExecLog CFG                                               \
    CC_FOR_BUILD="${CT_BUILD}-gcc"                                 \
    CFLAGS_FOR_TARGET="${aux_cflags}"                              \
    AR_FOR_TARGET="`which ${CT_TARGET}-gcc-ar`"                    \
    RANLIB_FOR_TARGET="`which ${CT_TARGET}-gcc-ranlib`"            \
    ${CONFIG_SHELL}                                                \
    "${CT_SRC_DIR}/newlib/configure"                               \
        --host=${CT_BUILD}                                         \
        --target=${CT_TARGET}                                      \
        --prefix=${CT_PREFIX_DIR}                                  \
        "${CT_LIBC_NEWLIB_AUX_BUILD_EXTRA_CONFIG_ARRAY[@]}"

    CT_DoLog EXTRA "Building auxiliary ${aux_name} C library"
    CT_DoExecLog ALL make ${JOBSFLAGS}

    CT_DoLog EXTRA "Installing auxiliary ${aux_name} C library"
    CT_DoExecLog ALL make install

    # Rename some files to *_aux_name.* pattern
    find ${CT_PREFIX_DIR}/${CT_TARGET}/lib \( -name libc.a -o -name libg.a \) -print0 |
        while IFS= read -r -d $'\0' name; do
            new_name=$(echo -n "${name%.*}"; echo -n "_${aux_name}."; echo "${name##*.}")
            mv -v ${name} ${new_name}
        done

    CT_EndStep
}
