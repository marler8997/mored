module more.types;

// Example:
// ---
// return boolstatus.pass;
// return boolstatus.fail;
// if(status.failed) ...
// if(status.passed) ...
struct passfail
{
    private bool _passed;
    @property static passfail pass() { return passfail(true); }
    @property static passfail fail() { return passfail(false); }
    @disable this();
    private this(bool _passed) { this._passed = _passed; }
    string toString() { return _passed ? "pass" : "fail"; }
}
@property auto passed(const(passfail) pf) { return pf._passed; }
@property auto failed(const(passfail) pf) { return !pf._passed; }
