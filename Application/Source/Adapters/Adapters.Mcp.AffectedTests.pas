unit Adapters.Mcp.AffectedTests;

// Host-Adapter zwischen Mcp und dem Host: get_affected_tests (#1353) fragt den Bericht über IMcpAffectedTests, der
// Host bestimmt die betroffenen Tests wie --affected-tests (TCoreAffectedTests) aus dem Unterschied laut Git oder SVN,
// dem Index des Arbeitsbereichs und den Optionen der Auswirkungsanalyse. Erzeugt nur in Shell.* und in Tests; kennt
// nur die Mcp-Contracts und den Host.

interface

uses
  System.SysUtils,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Mcp.Contract.AffectedTests,
  Atlas.Common.Mcp.Contract.Workspace,
  Core.VersionControlChanges;

type
  TMcpAffectedTestsAdapter = class(TInterfacedObject, IMcpAffectedTests)
  private
    FWorkspace: IMcpWorkspace;
    FAccess: TFunc<TCoreVcsAccess>;
    FImpactOptions: TImpactOptionsProvider;
  public
    /// <summary>AAccess liefert für jede Anfrage einen neuen Zugang zur Versionsverwaltung; AImpactOptions Tiefe,
    /// Treffersicherheit und Zeitlimit wie get_impact.</summary>
    constructor Create(const AWorkspace: IMcpWorkspace; const AAccess: TFunc<TCoreVcsAccess>;
      const AImpactOptions: TImpactOptionsProvider);
    /// <summary>Neuer Adapter als Interface (ohne Leck bei direkter Übergabe).</summary>
    class function New(const AWorkspace: IMcpWorkspace; const AAccess: TFunc<TCoreVcsAccess>;
      const AImpactOptions: TImpactOptionsProvider): IMcpAffectedTests; static;
    function Report(const AQuery: TMcpAffectedQuery; out AText, AError: string): Boolean;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.AffectedTests.Report,
  Atlas.Common.Lsp.AffectedTests.Types,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Localization.RequestTexts,
  Core.AffectedTests;

type
{$SCOPEDENUMS ON}
  TMcpAffectedText = (AllNeeded, NoneAffected);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpAffectedText] of TAtlasText = (
    (De: 'Alle Tests nötig: %s'; En: 'All tests needed: %s'),
    (De: 'Keine betroffenen Tests gegenüber %s.'; En: 'No affected tests compared with %s.'));

/// <summary>Format dunitx: nur das --run-Argument; ohne Argument sagt der Text warum.</summary>
function DUnitXText(const AFound: TAffectedResult): string;
begin
  if AFound.All then
  begin
    Result := cTexts[TMcpAffectedText.AllNeeded].Fmt([AFound.AllReason]);
  end
  else if Length(AFound.Tests) = 0 then
  begin
    Result := cTexts[TMcpAffectedText.NoneAffected].Fmt([AFound.Base]);
  end
  else if not TAffectedReport.DUnitXArgument(AFound, Result) then
  begin
    Result := cTexts[TMcpAffectedText.AllNeeded].Fmt([TCoreAffectedTests.TooManyForRun]);
  end;
end;

function CoreQueryOf(const AQuery: TMcpAffectedQuery): TCoreAffectedQuery;
begin
  Result := Default(TCoreAffectedQuery);
  Result.WorkingDir := AQuery.Root;
  Result.Base := AQuery.Base;
  Result.IncludeUncommitted := AQuery.IncludeUncommitted;
  Result.Depth := AQuery.Depth;
end;

{ TMcpAffectedTestsAdapter }

constructor TMcpAffectedTestsAdapter.Create(const AWorkspace: IMcpWorkspace; const AAccess: TFunc<TCoreVcsAccess>;
  const AImpactOptions: TImpactOptionsProvider);
begin
  inherited Create;
  FWorkspace := AWorkspace;
  FAccess := AAccess;
  FImpactOptions := AImpactOptions;
end;

class function TMcpAffectedTestsAdapter.New(const AWorkspace: IMcpWorkspace; const AAccess: TFunc<TCoreVcsAccess>;
  const AImpactOptions: TImpactOptionsProvider): IMcpAffectedTests;
begin
  Result := TMcpAffectedTestsAdapter.Create(AWorkspace, AAccess, AImpactOptions);
end;

function TMcpAffectedTestsAdapter.Report(const AQuery: TMcpAffectedQuery; out AText, AError: string): Boolean;
var
  mSettings: TServerSettings;
  mFormat: TAffectedFormat;
  mReadText: TReferenceReadText;
  mRequest: TAffectedRequest;
  mResolver: TNameResolver;
  mAccess: TCoreVcsAccess;
  mFound: TAffectedResult;
begin
  AText := '';
  AError := '';
  mSettings := FWorkspace.Settings;
  if not mSettings.Tests.Affected then
  begin
    AError := TCoreAffectedTests.OffMessage;
    Exit(False);
  end;
  if not TAffectedReport.TryParseFormat(AQuery.Format, mFormat) then
  begin
    AError := TRequestTexts.Choice('format', ['text', 'json', 'dunitx']);
    Exit(False);
  end;
  mReadText := TCoreAffectedTests.FileReader();
  // Dateien und Testprogramme der Gruppe; Treffersicherheit und Zeitlimit wie get_impact.
  mRequest := Default(TAffectedRequest);
  mRequest.Files := FWorkspace.AllFiles;
  mRequest.TestPrograms := TCoreAffectedTests.TestPrograms(mRequest.Files, mReadText);
  mRequest.Options := FImpactOptions('');
  // Testunits aus allen Testprogrammen der Gruppe.
  mRequest.Options.Tests := TCoreAffectedTests.TestScope(mSettings.TestUnits.Pattern, mRequest.TestPrograms,
    mReadText);
  // Über eine Variable halten: als const-Argument würde der Probelauf nie freigegeben.
  mAccess := FAccess();
  mResolver := TNameResolver.Create(FWorkspace.Index, FWorkspace.UnitLoader());
  try
    mResolver.Namespaces := FWorkspace.Namespaces;
    try
      mFound := TCoreAffectedTests.Run(mAccess, mSettings, CoreQueryOf(AQuery),
        TCoreAffectedSources.New(mResolver, FWorkspace.Index, mReadText), mRequest, nil);
    except
      on E: EVcsChanges do
      begin
        AError := E.Message;
        Exit(False);
      end;
    end;
  finally
    mResolver.Free;
  end;
  if mFormat = TAffectedFormat.DUnitX then
  begin
    AText := DUnitXText(mFound);
  end
  else
  begin
    AText := TAffectedReport.Render(mFound, mFormat);
  end;
  Result := True;
end;

initialization
  TAtlasTextTables.Add('Adapters.Mcp.AffectedTests', cTexts);

end.
