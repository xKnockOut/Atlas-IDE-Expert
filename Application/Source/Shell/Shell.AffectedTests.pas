unit Shell.AffectedTests;

// Host-Rolle Shell: betroffene Tests einer Änderung (#1353) für
// --affected-tests, das MCP-Werkzeug get_affected_tests und die LSP-Anfrage
// atlas/affectedTests. Holt den Unterschied wie --changed über TVcsChanges
// (Git oder SVN nach vcs.provider, mit geänderten Zeilen) und übergibt ihn an
// TAffectedTests.Determine.
//
// Basis: '' = Vorgabe, bei Git die Merge-Base mit main, bei SVN BASE. Eine
// eigene Basis vergleicht bei Git mit der Merge-Base dieser Basis und HEAD,
// bei SVN mit der Revision. Mit IncludeUncommitted zählen Index,
// Arbeitsverzeichnis und neue Dateien mit (bei SVN die unversionierten).
// tests.affected = false: EAffectedTestsOff.

interface

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.AffectedTests,
  Shell.VcsChanges;

type
  /// <summary>tests.affected ist aus.</summary>
  EAffectedTestsOff = class(Exception);

  TShellAffectedQuery = record
    /// <summary>Ordner in der Arbeitskopie; dort laufen git bzw. svn.</summary>
    WorkingDir: string;
    /// <summary>Ref bzw. Revision; '' = main (Git) bzw. BASE (SVN).</summary>
    Base: string;
    IncludeUncommitted: Boolean;
    /// <summary>1–5; 0 = tests.affectedDepth.</summary>
    Depth: Integer;
  end;

  TShellAffectedTests = class
  public const
    DefaultGitBase = 'main';
    SvnBase = 'BASE';
    OffMessage = 'Betroffene Tests sind ausgeschaltet (tests.affected)';
  public
    /// <summary>Geänderte Dateien samt Zeilen aus AChanges.</summary>
    class function Inputs(AChanges: TVcsChanges): TArray<TAffectedInput>; static;
    /// <summary>Hauptdateien (.dpr) unter AFiles, die DUnitX verwenden.</summary>
    class function TestPrograms(const AFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<string>;
      static;
    /// <summary>Testunits nach testUnits.pattern und den uses aller Testprogramme APrograms.</summary>
    class function TestScope(const APattern: string; const APrograms: TArray<string>;
      const AReadText: TReferenceReadText): TImpactTestScope; static;
    /// <summary>Ermittelt die betroffenen Tests. ARequest bringt Projektdateien, Testprogramme und Optionen (Tiefe
    /// wird aus AQuery bzw. tests.affectedDepth gesetzt); EAffectedTestsOff, wenn die Funktion aus ist,
    /// EVcsChanges ohne Arbeitskopie.</summary>
    class function Run(const AProcess: ICompilerProcess; const ASettings: TServerSettings;
      const AQuery: TShellAffectedQuery; AResolver: TNameResolver; const AIndex: ISymbolIndex;
      const ARequest: TAffectedRequest; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken): TAffectedResult; static;
  end;

implementation

uses
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

class function TShellAffectedTests.Inputs(AChanges: TVcsChanges): TArray<TAffectedInput>;
var
  mFile: string;
  mInput: TAffectedInput;
begin
  Result := nil;
  for mFile in AChanges.Files do
  begin
    mInput := Default(TAffectedInput);
    mInput.FileName := mFile;
    // Ohne Zeilen (umbenannt ohne Inhaltsänderung, binär) gilt die Datei als ganz geändert.
    mInput.HasLines := TChangedFiles.LinesOf(AChanges.Lines, AChanges.RepoRoot, mFile, mInput.Lines) and
      ((Length(mInput.Lines.Spans) > 0) or (Length(mInput.Lines.Gaps) > 0));
    Result := Result + [mInput];
  end;
end;

class function TShellAffectedTests.TestPrograms(const AFiles: TArray<string>;
  const AReadText: TReferenceReadText): TArray<string>;
var
  mFile, mText: string;
begin
  Result := nil;
  for mFile in AFiles do
    if SameText(ExtractFileExt(mFile), '.dpr') and Assigned(AReadText) and AReadText(mFile, mText) and
      TDUnitXSource.UsesDUnitX(TTextLines.SplitLines(mText)) then
      Result := Result + [mFile];
end;

class function TShellAffectedTests.TestScope(const APattern: string; const APrograms: TArray<string>;
  const AReadText: TReferenceReadText): TImpactTestScope;
var
  mProgram, mText: string;
begin
  Result := TImpactTestScope.FromProgram(APattern, '');
  for mProgram in APrograms do
    if Assigned(AReadText) and AReadText(mProgram, mText) then
      Result.Units := Result.Units + TImpactTestScope.FromProgram(APattern, mText).Units;
end;

class function TShellAffectedTests.Run(const AProcess: ICompilerProcess; const ASettings: TServerSettings;
  const AQuery: TShellAffectedQuery; AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const ARequest: TAffectedRequest; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TAffectedResult;
var
  mChanges: TVcsChanges;
  mRequest: TAffectedRequest;
  mRef: string;
begin
  if not ASettings.Tests.Affected then
    raise EAffectedTestsOff.Create(OffMessage);
  mRequest := ARequest;
  if AQuery.Depth > 0 then
    mRequest.Options.Depth := TImpactAnalysis.ClampDepth(AQuery.Depth)
  else
    mRequest.Options.Depth := TImpactAnalysis.ClampDepth(ASettings.Tests.AffectedDepth);
  mChanges := TVcsChanges.Detect(AProcess, AQuery.WorkingDir, ASettings.VcsProvider, ASettings.VcsGitPath,
    ASettings.VcsSvnPath, ASettings.VcsTimeoutSeconds);
  try
    mRef := AQuery.Base;
    if mRef = '' then
      mRef := DefaultGitBase;
    // Wie --changed: ohne eigene Basis vergleicht SVN mit BASE (svn status), Git mit der Merge-Base.
    mChanges.Load(mRef, True, AQuery.Base = '', AQuery.IncludeUncommitted, True);
    if (AQuery.Base = '') and (mChanges is TSvnChanges) then
      mRequest.Base := SvnBase
    else
      mRequest.Base := mRef;
    Result := TAffectedTests.Determine(AResolver, AIndex, Inputs(mChanges), mRequest, AReadText, ACancellation);
  finally
    mChanges.Free;
  end;
end;

end.
