class MysqlAT56 < Formula
  desc "Open source relational database management system"
  homepage "https://dev.mysql.com/doc/refman/5.6/en/"
  # dev.mysql.com 的 5.6 下载已失效（403），换 cdn 归档地址
  url "https://cdn.mysql.com/Downloads/MySQL-5.6/mysql-5.6.51.tar.gz"
  sha256 "262ccaf2930fca1f33787505dd125a7a04844f40d3421289a51974b5935d9abc"
  license "GPL-2.0-only"
  revision 1

  bottle do
    rebuild 1
    sha256 monterey:     "e3132c3b1381b6ea6a2298166866e637560b0be3223912d1512a150b096fa104"
    sha256 big_sur:      "30a530ddb785efe7542641366126d7b4afcce09bde0fa104b869814fa69fc9e2"
    sha256 catalina:     "a5309a985dccc02490ff9bd0be1575a4e8908ca3e15dcfaa77e7d2b2bd616cfd"
    sha256 mojave:       "1ba2347383b539258d1c0a29cbbee722c30e6c28446c22a669a8a7deabd5f53e"
    sha256 x86_64_linux: "91b24798f46a2bc7b616fb73fc47a5337acb5b8e0a6f9be1c657eade6fade45b"
  end

  keg_only :versioned_formula

  deprecate! date: "2021-02-01", because: :unsupported

  depends_on "cmake" => :build
  depends_on "openssl@1.1"

  uses_from_macos "libedit"

  def datadir
    var/"mysql"
  end

  # Fixes loading of VERSION file, backported from mysql/mysql-server@51675dd
  patch :DATA

  def install
    # Don't hard-code the libtool path. See:
    # https://github.com/Homebrew/homebrew/issues/20185
    inreplace "cmake/libutils.cmake",
      "COMMAND /usr/bin/libtool -static -o ${TARGET_LOCATION}",
      "COMMAND libtool -static -o ${TARGET_LOCATION}"

    # Fix loading of VERSION file; required in conjunction with patch
    File.rename "VERSION", "MYSQL_VERSION"

    # CMake 4.x 兼容修复 1：这 6 个老策略在 CMake 4.x 已不再允许 SET ... OLD。
    # 直接注释掉，让 CMake 用 NEW 行为。5.6 比 5.7 多 CMP0026 和 CMP0075。
    %w[CMP0018 CMP0022 CMP0026 CMP0042 CMP0045 CMP0075].each do |policy|
      inreplace "CMakeLists.txt",
                "CMAKE_POLICY(SET #{policy} OLD)",
                "# CMAKE_POLICY(SET #{policy} OLD) [removed for CMake 4.x]"
    end

    # CMake 4.x 兼容修复 2：CMP0045 NEW 行为下，GET_TARGET_PROPERTY 对非 target 直接报错。
    # 5.6 的 libutils.cmake 在 MERGE_LIBRARIES 里对 LIBS_TO_MERGE 元素做了两次 GET_TARGET_PROPERTY，
    # 用 IF(TARGET) 守卫一下，非 target 走 OSLIB 分支。
    inreplace "cmake/libutils.cmake",
              "  FOREACH(LIB ${LIBS_TO_MERGE})\n    GET_TARGET_PROPERTY(LIB_LOCATION ${LIB} LOCATION)\n    GET_TARGET_PROPERTY(LIB_TYPE ${LIB} TYPE)",
              "  FOREACH(LIB ${LIBS_TO_MERGE})\n    IF(TARGET ${LIB})\n      GET_TARGET_PROPERTY(LIB_LOCATION ${LIB} LOCATION)\n      GET_TARGET_PROPERTY(LIB_TYPE ${LIB} TYPE)\n    ELSE()\n      SET(LIB_LOCATION \"LIB_LOCATION-NOTFOUND\")\n      SET(LIB_TYPE \"LIB_TYPE-NOTFOUND\")\n    ENDIF()"

    # macOS 根治补丁（与 mysql@5.7 同款）：vio/viosocket.c 的 vio_io_wait（握手等
    # socket 可读以读 auth 包就走这里）被 `#if !defined(_WIN32) && !defined(__APPLE__)`
    # 排除在 poll() 实现之外，macOS 强制落到 select() 版。5.6 的 select() 版连
    # 5.7 那个 `if (fd >= FD_SETSIZE) DBUG_RETURN(-1)` 守卫都没有，且 5.6 formula
    # 无 -DFD_SETSIZE（fd_set 按默认 __DARWIN_FD_SETSIZE=1024）：当 mysqld 打开的
    # fd 被 table cache 撑高（DataGrip 内省全部库 / MCP 枚举全表），新连接 socket
    # 的 fd 号 ≥1024 时，FD_SET/FD_ISSET 越界（现代 macOS SDK 经
    # __darwin_check_fd_set_overflow 变静默 no-op）→ select 永远等不到就绪 →
    # vio_io_wait 误判 → 握手被丢弃（server 刷 "Got an error reading
    # communication packets"、Aborted_connects 飙升；client 报 "Lost connection
    # at reading authorization packet"）。
    # 修法：让 macOS 也走已存在的 poll() 版 vio_io_wait（poll 无 FD_SETSIZE 上限，
    # MySQL 8.0 即如此），从根上拆掉这条 select() 路径。该 #if 在 viosocket.c 内
    # 唯一，inreplace 找不到会让构建失败，可防版本漂移。5.6 listener 在
    # sql/mysqld.cc 走 HAVE_POLL 的 poll()，无此问题，故只需这一处、不需 FD_SETSIZE。
    if OS.mac?
      inreplace "vio/viosocket.c",
                "#if !defined(_WIN32) && !defined(__APPLE__)",
                "#if !defined(_WIN32) /* [macOS 根治: vio_io_wait 改走 poll(), 去掉 FD_SETSIZE 上限] */"
    end

    # -DINSTALL_* are relative to `CMAKE_INSTALL_PREFIX` (`prefix`)
    args = %W[
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
      -DCOMPILATION_COMMENT=Homebrew
      -DDEFAULT_CHARSET=utf8
      -DDEFAULT_COLLATION=utf8_general_ci
      -DINSTALL_DOCDIR=share/doc/#{name}
      -DINSTALL_INCLUDEDIR=include/mysql
      -DINSTALL_INFODIR=share/info
      -DINSTALL_MANDIR=share/man
      -DINSTALL_MYSQLSHAREDIR=share/mysql
      -DMYSQL_DATADIR=#{datadir}
      -DSYSCONFDIR=#{etc}
      -DWITH_EDITLINE=system
      -DWITH_NUMA=OFF
      -DWITH_SSL=yes
      -DWITH_UNIT_TESTS=OFF
      -DWITH_EMBEDDED_SERVER=ON
      -DWITH_ARCHIVE_STORAGE_ENGINE=1
      -DWITH_BLACKHOLE_STORAGE_ENGINE=1
      -DENABLED_LOCAL_INFILE=1
      -DWITH_INNODB_MEMCACHED=ON
    ]

    system "cmake", ".", *std_cmake_args, *args
    system "make"
    system "make", "install"

    # Avoid references to the Homebrew shims directory
    inreplace bin/"mysqlbug", "#{Superenv.shims_path}/", ""

    (prefix/"mysql-test").cd do
      system "./mysql-test-run.pl", "status", "--vardir=#{Dir.mktmpdir}"
    end

    # Remove the tests directory
    rm_rf prefix/"mysql-test"

    # Don't create databases inside of the prefix!
    # See: https://github.com/Homebrew/homebrew/issues/4975
    rm_rf prefix/"data"

    # Link the setup script into bin
    bin.install_symlink prefix/"scripts/mysql_install_db"

    # Fix up the control script and link into bin.
    inreplace "#{prefix}/support-files/mysql.server",
              /^(PATH=".*)(")/,
              "\\1:#{HOMEBREW_PREFIX}/bin\\2"
    bin.install_symlink prefix/"support-files/mysql.server"

    libexec.install bin/"mysqlaccess"
    libexec.install bin/"mysqlaccess.conf"

    # Install my.cnf that binds to 127.0.0.1 by default
    (buildpath/"my.cnf").write <<~EOS
      # Default Homebrew MySQL server config
      [mysqld]
      # Only allow connections from localhost
      bind-address = 127.0.0.1
    EOS
    etc.install "my.cnf"
  end

  def post_install
    # Make sure the var/mysql directory exists
    (var/"mysql").mkpath

    # Don't initialize database, it clashes when testing other MySQL-like implementations.
    return if ENV["HOMEBREW_GITHUB_ACTIONS"]

    unless (datadir/"mysql/general_log.CSM").exist?
      ENV["TMPDIR"] = nil
      system bin/"mysql_install_db", "--verbose", "--user=#{ENV["USER"]}",
        "--basedir=#{prefix}", "--datadir=#{datadir}", "--tmpdir=/tmp"
    end
  end

  def caveats
    <<~EOS
      A "/etc/my.cnf" from another install may interfere with a Homebrew-built
      server starting up correctly.

      MySQL is configured to only allow connections from localhost by default

      To connect:
          mysql -uroot
    EOS
  end

  service do
    run [opt_bin/"mysqld_safe", "--datadir=#{var}/mysql"]
    keep_alive true
    working_dir var/"mysql"
  end

  test do
    (testpath/"mysql").mkpath
    (testpath/"tmp").mkpath
    system bin/"mysql_install_db", "--no-defaults", "--user=#{ENV["USER"]}",
      "--basedir=#{prefix}", "--datadir=#{testpath}/mysql", "--tmpdir=#{testpath}/tmp"
    port = free_port
    fork do
      system "#{bin}/mysqld", "--no-defaults", "--user=#{ENV["USER"]}",
        "--datadir=#{testpath}/mysql", "--port=#{port}", "--tmpdir=#{testpath}/tmp"
    end
    sleep 5
    assert_match "information_schema",
      shell_output("#{bin}/mysql --port=#{port} --user=root --password= --execute='show databases;'")
    system "#{bin}/mysqladmin", "--port=#{port}", "--user=root", "--password=", "shutdown"
  end
end

__END__
diff --git a/cmake/mysql_version.cmake b/cmake/mysql_version.cmake
index 34ed6f4..4becbbc 100644
--- a/cmake/mysql_version.cmake
+++ b/cmake/mysql_version.cmake
@@ -31,7 +31,7 @@ SET(DOT_FRM_VERSION "6")

 # Generate "something" to trigger cmake rerun when VERSION changes
 CONFIGURE_FILE(
-  ${CMAKE_SOURCE_DIR}/VERSION
+  ${CMAKE_SOURCE_DIR}/MYSQL_VERSION
   ${CMAKE_BINARY_DIR}/VERSION.dep
 )

@@ -39,7 +39,7 @@ CONFIGURE_FILE(

 MACRO(MYSQL_GET_CONFIG_VALUE keyword var)
  IF(NOT ${var})
-   FILE (STRINGS ${CMAKE_SOURCE_DIR}/VERSION str REGEX "^[ ]*${keyword}=")
+   FILE (STRINGS ${CMAKE_SOURCE_DIR}/MYSQL_VERSION str REGEX "^[ ]*${keyword}=")
    IF(str)
      STRING(REPLACE "${keyword}=" "" str ${str})
      STRING(REGEX REPLACE  "[ ].*" ""  str "${str}")
