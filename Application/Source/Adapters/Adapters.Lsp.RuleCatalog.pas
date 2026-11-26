unit Adapters.Lsp.RuleCatalog;

// Host-Adapter zwischen Rules und Lsp: Befunde und Vervollständigung des Sprachservers fragen ILspRuleCatalog; die
// Angaben liefert der Regelkatalog über IRuleCatalogInfo. Erzeugt nur in Shell.Composition.*; kennt nur die beiden
// Contracts.

interface

uses
  Atlas.Common.Findings.Contract,
  Lsp.Contract,
  Rules.Contract.Api;

type
  /// <summary>ILspRuleCatalog über die API der Prüfregeln.</summary>
  TLspRuleCatalogAdapter = class(TInterfacedObject, ILspRuleCatalog)
  private
    FCatalog: IRuleCatalogInfo;
  public
    constructor Create(const ACatalog: IRuleCatalogInfo);
    function RuleIds: TArray<string>;
    function TryDescribe(const ARuleId: string; out AFacts: TLspRuleFacts): Boolean;
    function HelpUri(const ARuleId: string): string;
    function StruckThrough(const AFinding: TRuleFinding): Boolean;
    /// <summary>Adapter über ACatalog; nil ohne.</summary>
    class function Wrap(const ACatalog: IRuleCatalogInfo): ILspRuleCatalog; static;
  end;

implementation

constructor TLspRuleCatalogAdapter.Create(const ACatalog: IRuleCatalogInfo);
begin
  inherited Create;
  FCatalog := ACatalog;
end;

function TLspRuleCatalogAdapter.RuleIds: TArray<string>;
begin
  Result := FCatalog.RuleIds;
end;

function TLspRuleCatalogAdapter.TryDescribe(const ARuleId: string; out AFacts: TLspRuleFacts): Boolean;
var
  mFacts: TRuleCatalogFacts;
begin
  AFacts := Default(TLspRuleFacts);
  Result := FCatalog.TryDescribe(ARuleId, mFacts);
  if Result then
  begin
    AFacts.Category := mFacts.Category;
    AFacts.Group := mFacts.Group;
    AFacts.CompilerCodes := mFacts.CompilerCodes;
  end;
end;

function TLspRuleCatalogAdapter.HelpUri(const ARuleId: string): string;
begin
  Result := FCatalog.HelpUri(ARuleId);
end;

function TLspRuleCatalogAdapter.StruckThrough(const AFinding: TRuleFinding): Boolean;
begin
  Result := FCatalog.StruckThrough(AFinding);
end;

class function TLspRuleCatalogAdapter.Wrap(const ACatalog: IRuleCatalogInfo): ILspRuleCatalog;
begin
  Result := nil;
  if ACatalog <> nil then
  begin
    Result := TLspRuleCatalogAdapter.Create(ACatalog);
  end;
end;

end.
