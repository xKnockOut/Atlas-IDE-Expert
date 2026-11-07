unit Atlas.IDE.Rules.BulkFix;

// Sammelkorrektur im Modul Prüfregeln (#1352, #1455): „Alle sicheren Treffer
// von <Regel> korrigieren …“ im Kontextmenü von „Atlas-Prüfung“, nur mit
// fix.bulk. Das Fenster (Base) fragt laufende Module nach IAtlasBulkFixer.
// Dateien der angezeigten Befunde dieser Regel an atlas.server.fixFindings
// (über TAtlasIdeHost, nebenläufig und mit längerer Frist: Der Server prüft
// alle Dateien der Regel), Vorschau (TAtlasBulkFixDialog), die gewählten
// Dateien über TAtlasIdeWorkspaceEdit (ein Rückgängig-Schritt je Datei, ein
// Satz im Änderungsprotokoll); Regel, Anzahl und Dateien stehen danach in der
// Meldungsansicht. Die Antwort erreicht das Modul nur, solange es angemeldet
// ist (Regel 3).

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.Core.Problems.Findings;

type
  TAtlasIdeRulesBulkFix = class(TInterfacedObject, IAtlasBulkFixer)
  private
    FScope: IAtlasModuleScope;
  public
    constructor Create(const AScope: IAtlasModuleScope);
    function CanFixAll: Boolean;
    procedure FixAll(const ARule: string; const AFindings: TArray<TAtlasFinding>);
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Problems.BulkFix,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.UI.Problems.BulkFix,
  Atlas.UI.Strings,
  Atlas.UI.Rules.Strings;

const
  /// <summary>Der Server prüft alle Dateien der Regel; das dauert länger als ein Befehl sonst.</summary>
  cFixTimeoutMs = 300000;

/// <summary>Vorschau zur Antwort von atlas.server.fixFindings und die gewählten Dateien anwenden.</summary>
procedure ShowPreview(const ARule: string; AAnswer: TJSONValue);
var
  mPreview: TAtlasBulkFixPreview;
  mError: string;
  mFixes, mCount, mIndex: Integer;
  mNames: TArray<string>;
begin
  mPreview := TAtlasBulkFixPreview.Create(ARule, AAnswer);
  try
    if mPreview.Count = 0 then
    begin
      TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsFixAllNothing, [ARule, mPreview.Summary]));
      Exit;
    end;
    if not TAtlasBulkFixDialog.Execute(mPreview) then
    begin
      Exit;
    end;
    mFixes := mPreview.SelectedFixes;
    mCount := mPreview.SelectedCount;
    mNames := nil;
    for mIndex := 0 to mPreview.Count - 1 do
    begin
      if mPreview.Files[mIndex].Checked then
      begin
        mNames := mNames + [ExtractFileName(mPreview.Files[mIndex].FileName)];
      end;
    end;
    mError := TAtlasIdeWorkspaceEdit.Apply(mPreview.SelectedEdit,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsFixAllAction, [ARule])).Error;
    if mError <> '' then
    begin
      TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsFixAllFailed, [ARule, mError]));
    end
    else
    begin
      TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsFixAllDone, [ARule, mFixes, mCount,
        string.Join(', ', mNames)]));
    end;
  finally
    mPreview.Free;
  end;
end;

/// <summary>Antwort des Servers (Hauptthread); eigene Routine, damit der Rahmen nur die Regel hält.</summary>
function FixAnswer(const ARule: string): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mValue: TJSONValue;
    begin
      if AAnswer = '' then
      begin
        TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.ProblemsNoServer));
        Exit;
      end;
      mValue := TJSONValue.ParseJSONValue(AAnswer);
      try
        if mValue = nil then
        begin
          TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.ProblemsNoServer));
          Exit;
        end;
        TAtlasGuard.Run(TAtlasFeature.Problems,
          procedure
          begin
            ShowPreview(ARule, mValue);
          end);
      finally
        mValue.Free;
      end;
    end;
end;

{ TAtlasIdeRulesBulkFix }

constructor TAtlasIdeRulesBulkFix.Create(const AScope: IAtlasModuleScope);
begin
  inherited Create;
  FScope := AScope;
end;

function TAtlasIdeRulesBulkFix.CanFixAll: Boolean;
begin
  Result := TAtlasIdeSettings.Current.FixBulk;
end;

procedure TAtlasIdeRulesBulkFix.FixAll(const ARule: string; const AFindings: TArray<TAtlasFinding>);
var
  mFiles: TArray<string>;
begin
  if not CanFixAll then
  begin
    Exit;
  end;
  mFiles := TAtlasBulkFixPreview.FilesOf(AFindings, ARule);
  if mFiles = nil then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsFixAllNoFiles, [ARule]));
    Exit;
  end;
  if not TAtlasIdeHost.RunServerCommandAsync(FScope, TAtlasFeature.Problems, TAtlasBulkFixPreview.cCommand,
    TAtlasBulkFixPreview.ArgumentsJson(ARule, mFiles), cFixTimeoutMs, FixAnswer(ARule)) then
  begin
    TAtlasIdeHost.Message(TAtlasStrings.Text(TAtlasTextId.ProblemsNoServer));
  end;
end;

end.
