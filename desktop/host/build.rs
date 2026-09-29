// Windows: the .exe's icon and version info (Explorer, the taskbar, Apps & features).
fn main() {
    println!("cargo:rerun-if-changed=../packaging/icons/wake.ico");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let mut resource = winresource::WindowsResource::new();
        resource
            .set_icon("../packaging/icons/wake.ico")
            .set("ProductName", "Wake")
            .set("FileDescription", "Wake")
            .set("CompanyName", "Amirali Beigi")
            .set("LegalCopyright", "Amirali Beigi");
        if let Err(error) = resource.compile() {
            println!("cargo:warning=couldn't embed the Windows icon: {error}");
        }
    }
}
