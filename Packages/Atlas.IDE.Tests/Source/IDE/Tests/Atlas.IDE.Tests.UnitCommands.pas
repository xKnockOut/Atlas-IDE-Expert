unit Atlas.IDE.Tests.UnitCommands;

// Befehle des Moduls Tests rund um Testunits:
// - „Tests dieser Unit ausführen“ im Kontextmenü der Projektverwaltung
//   (#1817): Testunits der gewählten Units nach Namen in der Projektgruppe,
//   nur solche mit Fixtures; ohne eine meldet das Modul es in der
//   Meldungsansicht.
// - Assistent „DUnitX-Testunit zu Unit …“ in Datei › Neu › Weitere (#1821):
//   Unit der Projektgruppe wählen, die Unit im Editor vorgewählt; angelegt wie
//   „Zur Testunit wechseln“ von Base.
// Anmeldung und Sichtbarkeit regelt Atlas.IDE.Tests.Composition. Nur im
// Hauptthread.

interface

uses
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestUnitCommands = class
  public
    /// <summary>Hat die Auswahl der Projektverwaltung Units?</summary>
    class function HasProjectUnits: Boolean; static;
    /// <summary>Tests der gewählten Units über ATests ausführen; nil = nichts.</summary>
    class procedure RunProjectUnits(ATests: TAtlasIdeTests); static;
    /// <summary>Assistent „DUnitX-Testunit zu Unit …“ (#1821): Unit wählen, dann wie „Zur Testunit wechseln“.
    /// </summary>
    class procedure NewTestUnitFor; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Tests.UnitMatch,
  Atlas.Core.Commands.ProjectSelection,
  Atlas.Text.DUnitX,
  Atlas.IDE.Problems.Files,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Commands.Editor,
  Atlas.UI.Generate.Choice,
  Atlas.UI.Tests.Strings;

/// <summary>Testunits (mit Fixtures) der Units AUnits unter AFiles und die vollen Namen ihrer Fixtures.</summary>
function FindUnitTests(const AUnits, AFiles: TArray<string>; out ANames: TArray<string>): TArray<string>;
var
  mUnit, mCandidate: string;
  mNames: TArray<string>;
begin
  Result := nil;
  ANames := nil;
  for mUnit in AUnits do
  begin
    for mCandidate in TAtlasTestUnitMatch.Candidates(mUnit, AFiles) do
    begin
      mNames := TAtlasTestUnitMatch.Names(TDUnitXSource.Scan(TAtlasIdeProblemFiles.DiskLines(mCandidate)));
      if Length(mNames) > 0 then
      begin
        Result := Result + [mCandidate];
        ANames := ANames + mNames;
      end;
    end;
  end;
end;

class procedure TAtlasIdeTestUnitCommands.RunProjectUnits(ATests: TAtlasIdeTests);
var
  mSelection: TAtlasProjectSelection;
  mKey: string;
  mTestUnits, mNames: TArray<string>;
begin
  mSelection := TAtlasProjectContext.Current;
  if (ATests = nil) or not mSelection.HasUnits then
  begin
    Exit;
  end;
  mTestUnits := FindUnitTests(mSelection.Units, TAtlasIdeProblemFiles.GroupFiles(mKey), mNames);
  if Length(mTestUnits) = 0 then
  begin
    TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsProjectNoTestUnit,
      [ExtractFileName(mSelection.Units[0])]));
    Exit;
  end;
  // Das Testprojekt bestimmt die erste Testunit; die Namen gelten für alle gefundenen.
  ATests.RunTests(mTestUnits[0], mNames, False);
end;

class function TAtlasIdeTestUnitCommands.HasProjectUnits: Boolean;
begin
  Result := TAtlasProjectContext.Active and TAtlasProjectContext.Current.HasUnits;
end;

class procedure TAtlasIdeTestUnitCommands.NewTestUnitFor;
var
  mKey, mActive: string;
  mUnits, mNames: TArray<string>;
  mUnit: string;
  mIndex: Integer;
  mView: IOTAEditView;
begin
  mUnits := TAtlasTestUnitMatch.Units(TAtlasIdeProblemFiles.GroupFiles(mKey));
  if Length(mUnits) = 0 then
  begin
    TAtlasIdeHost.Message(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsGalleryNoUnits));
    Exit;
  end;
  mNames := nil;
  for mUnit in mUnits do
  begin
    mNames := mNames + [TAtlasTestUnitMatch.UnitNameOf(mUnit)];
  end;
  mActive := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mActive := mView.Buffer.FileName;
  end;
  mIndex := TAtlasTestUnitMatch.IndexOf(mUnits, mActive);
  if TAtlasChoiceDialog.Execute(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsGalleryTestUnit),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsGalleryChooseUnit), mNames, mIndex) then
  begin
    TAtlasIdeEditorCommands.TestUnitFor(mUnits[mIndex]);
  end;
end;

end.
