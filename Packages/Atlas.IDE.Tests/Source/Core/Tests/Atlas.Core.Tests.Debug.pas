unit Atlas.Core.Tests.Debug;

// Einzelnen DUnitX-Test im Debugger starten (#585), Teil ohne VCL und Open
// Tools API:
// - Auswahl: welcher Test an einer Zeile steht (Code Lens, Befehl am Cursor,
//   Kontextmenü) bzw. zu einem vollen Namen gehört (Willkommensseite #763),
//   mit den Namen für --run (Atlas.Text.DUnitX: [TestCase]-Fälle einzeln)
//   und der Zeile der ersten Anweisung für den einmaligen Haltepunkt.
// - Startparameter: Die vorhandenen Parameter des Testprojekts bleiben,
//   Optionen, die den Filter oder das Ende stören (--run, --runlist,
//   --include, --exclude, --xmlfile, --exitbehavior, Hilfe), fallen weg;
//   dazu kommen --run:<Namen>, --exitbehavior:Continue (sonst wartet das
//   Programm am Ende auf Enter und die Sitzung endet nicht) und der
//   XML-Bericht für das Ergebnis wie in #69. Atlas setzt sie über die
//   Startprofile (#575) vorübergehend und stellt danach die alten wieder her.
// - Schalter: Lens, Befehle und Haltepunkt nach den Einstellungen.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Text.DUnitX;

type
  /// <summary>Ein Test, ein Fall oder eine Fixture zum Ausführen oder Debuggen.</summary>
  TAtlasTestSelection = record
    UnitName: string;
    Fixture: string;
    /// <summary>'' = die ganze Fixture.</summary>
    Method: string;
    /// <summary>'' = alle Fälle bzw. kein [TestCase].</summary>
    CaseName: string;
    /// <summary>Namen für --run.</summary>
    Names: TArray<string>;
    /// <summary>Zeile der ersten Anweisung der Methode (0-basiert); -1 ohne (Fixture, Rumpf unbekannt).</summary>
    BreakLine: Integer;
    /// <summary>Für Meldungen: Fixture.Methode[.Fall] bzw. Fixture.</summary>
    function Caption: string;
  end;

  TAtlasTestDebug = class
  public const
    /// <summary>So lange wartet Atlas nach „Start“ auf den Prozess, bevor es die Startparameter zurückstellt.
    /// </summary>
    StartTimeoutMs = 60000;
  public
    /// <summary>Auswahl für Fixture AFixtureIndex, Test ATestIndex (-1 = Fixture) und Fall ACaseIndex (-1 = alle).
    /// </summary>
    class function Selection(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
      ACaseIndex: Integer): TAtlasTestSelection; static;
    /// <summary>Test an ALine (0-basiert, TDUnitXUnit.TestAt); False ohne.</summary>
    class function SelectAt(const AUnit: TDUnitXUnit; ALine: Integer; out ASelection: TAtlasTestSelection): Boolean;
      static;
    /// <summary>Test zum vollen Namen Unit.Fixture.Methode[.Fall] bzw. Fixture.Methode (Willkommensseite #763,
    /// erneut ausführen); False, wenn es ihn in AUnit nicht gibt.</summary>
    class function SelectByName(const AUnit: TDUnitXUnit; const AFullName: string;
      out ASelection: TAtlasTestSelection): Boolean; static;
    /// <summary>Befehlszeile in Argumente zerlegen wie Windows (Leerraum trennt, Anführungszeichen schützen);
    /// die Argumente bleiben roh, mit ihren Anführungszeichen.</summary>
    class function SplitArguments(const AText: string): TArray<string>; static;
    /// <summary>Argument in Anführungszeichen, wenn es Leerraum enthält.</summary>
    class function QuoteArgument(const AValue: string): string; static;
    /// <summary>Name einer DUnitX-Option klein, ohne -, -- bzw. / und ohne Wert („--RUN:x“ → „run“); '' für
    /// Argumente ohne Optionszeichen.</summary>
    class function OptionName(const AArgument: string): string; static;
    /// <summary>Startparameter für den Lauf: AExisting ohne störende Optionen, dann --run:ANames,
    /// --exitbehavior:Continue und, wenn AXmlFile nicht leer ist, --xmlfile:AXmlFile.</summary>
    class function Parameters(const AExisting: string; const ANames: TArray<string>;
      const AXmlFile: string): string; static;
    /// <summary>„Test debuggen“ (Befehl, Kontextmenü, Marke der Code Lens) verfügbar: Atlas an, Tests ausführen
    /// (TestRun), Test debuggen (TestDebug) und codeLens.tests (#585: aus = wie ohne die Funktion).</summary>
    class function DebugWanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>„Test ausführen“ am Cursor verfügbar: Atlas an, Tests ausführen (TestRun) und codeLens.tests.</summary>
    class function RunWanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Code Lens an Tests: Atlas an, codeLens.tests und TestRun; ohne sie verhält sich Atlas wie ohne
    /// Lens (#585, gemeinsamer Schlüssel mit #69).</summary>
    class function LensWanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Marke „Debuggen“ neben „Test ausführen“: LensWanted und DebugWanted.</summary>
    class function LensDebugWanted(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Einmaligen Haltepunkt setzen: debug.testBreakAtStart an und die Zeile bekannt.</summary>
    class function BreakWanted(const ASettings: TAtlasPluginSettings; const ASelection: TAtlasTestSelection): Boolean;
      static;
  end;

implementation

const
  /// <summary>Optionen von DUnitX (lang und kurz), die Atlas beim Debuggen weglässt.</summary>
  DroppedOptions: array[0..13] of string = ('run', 'r', 'runlist', 'rl', 'include', 'i', 'exclude', 'e',
    'xmlfile', 'xml', 'exitbehavior', 'exit', 'h', '?');

{ TAtlasTestSelection }

function TAtlasTestSelection.Caption: string;
begin
  Result := Fixture;
  if Method <> '' then
    Result := Result + '.' + Method;
  if CaseName <> '' then
    Result := Result + '.' + CaseName;
end;

{ TAtlasTestDebug }

class function TAtlasTestDebug.Selection(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
  ACaseIndex: Integer): TAtlasTestSelection;
var
  Test: TDUnitXTest;
begin
  Result := Default(TAtlasTestSelection);
  Result.BreakLine := -1;
  if (AFixtureIndex < 0) or (AFixtureIndex > High(AUnit.Fixtures)) then
    Exit;
  Result.UnitName := AUnit.UnitName;
  Result.Fixture := AUnit.Fixtures[AFixtureIndex].Name;
  Result.Names := TDUnitXCommandLine.RunNames(AUnit, AFixtureIndex, ATestIndex, ACaseIndex);
  if (ATestIndex < 0) or (ATestIndex > High(AUnit.Fixtures[AFixtureIndex].Tests)) then
    Exit;
  Test := AUnit.Fixtures[AFixtureIndex].Tests[ATestIndex];
  Result.Method := Test.Method;
  if (ACaseIndex >= 0) and (ACaseIndex <= High(Test.Cases)) and not Test.Ignored then
    Result.CaseName := Test.Cases[ACaseIndex];
  Result.BreakLine := Test.BeginLine;
end;

class function TAtlasTestDebug.SelectAt(const AUnit: TDUnitXUnit; ALine: Integer;
  out ASelection: TAtlasTestSelection): Boolean;
var
  FixtureIndex, TestIndex, CaseIndex: Integer;
begin
  ASelection := Default(TAtlasTestSelection);
  ASelection.BreakLine := -1;
  Result := AUnit.TestAt(ALine, FixtureIndex, TestIndex, CaseIndex);
  if Result then
    ASelection := Selection(AUnit, FixtureIndex, TestIndex, CaseIndex);
end;

class function TAtlasTestDebug.SelectByName(const AUnit: TDUnitXUnit; const AFullName: string;
  out ASelection: TAtlasTestSelection): Boolean;
var
  FixtureIndex, TestIndex, CaseIndex: Integer;
  Fixture: TDUnitXFixture;
  Test: TDUnitXTest;
  Name, Prefix: string;
begin
  ASelection := Default(TAtlasTestSelection);
  ASelection.BreakLine := -1;
  Name := Trim(AFullName);
  // Der Unitname steht davor oder fehlt (Fixture.Methode).
  if (AUnit.UnitName <> '') and SameText(Copy(Name, 1, Length(AUnit.UnitName) + 1), AUnit.UnitName + '.') then
    Name := Copy(Name, Length(AUnit.UnitName) + 2, MaxInt);
  for FixtureIndex := 0 to High(AUnit.Fixtures) do
  begin
    Fixture := AUnit.Fixtures[FixtureIndex];
    if SameText(Name, Fixture.Name) then
    begin
      ASelection := Selection(AUnit, FixtureIndex, -1, -1);
      Exit(True);
    end;
    for TestIndex := 0 to High(Fixture.Tests) do
    begin
      Test := Fixture.Tests[TestIndex];
      Prefix := Fixture.Name + '.' + Test.Method;
      if SameText(Name, Prefix) then
      begin
        ASelection := Selection(AUnit, FixtureIndex, TestIndex, -1);
        Exit(True);
      end;
      for CaseIndex := 0 to High(Test.Cases) do
        if SameText(TDUnitXCommandLine.CaseName('', Fixture.Name, Test.Method, Test.Cases[CaseIndex]), Name) then
        begin
          ASelection := Selection(AUnit, FixtureIndex, TestIndex, CaseIndex);
          Exit(True);
        end;
    end;
  end;
  Result := False;
end;

class function TAtlasTestDebug.SplitArguments(const AText: string): TArray<string>;
var
  Index: Integer;
  Current: string;
  Quoted, Started: Boolean;
begin
  Result := nil;
  Current := '';
  Quoted := False;
  Started := False;
  for Index := 1 to Length(AText) do
  begin
    if not Quoted and ((AText[Index] = ' ') or (AText[Index] = #9) or (AText[Index] = #13) or
      (AText[Index] = #10)) then
    begin
      if Started then
        Result := Result + [Current];
      Current := '';
      Started := False;
      Continue;
    end;
    if AText[Index] = '"' then
      Quoted := not Quoted;
    Current := Current + AText[Index];
    Started := True;
  end;
  if Started then
    Result := Result + [Current];
end;

class function TAtlasTestDebug.QuoteArgument(const AValue: string): string;
begin
  Result := AValue;
  if (Pos(' ', AValue) > 0) or (Pos(#9, AValue) > 0) then
    Result := '"' + StringReplace(AValue, '"', '', [rfReplaceAll]) + '"';
end;

class function TAtlasTestDebug.OptionName(const AArgument: string): string;
var
  Text: string;
  Colon: Integer;
begin
  Result := '';
  Text := StringReplace(AArgument, '"', '', [rfReplaceAll]);
  if Copy(Text, 1, 2) = '--' then
    Delete(Text, 1, 2)
  else if (Copy(Text, 1, 1) = '-') or (Copy(Text, 1, 1) = '/') then
    Delete(Text, 1, 1)
  else
    Exit;
  Colon := Pos(':', Text);
  if Colon > 0 then
    Text := Copy(Text, 1, Colon - 1);
  Result := LowerCase(Text);
end;

class function TAtlasTestDebug.Parameters(const AExisting: string; const ANames: TArray<string>;
  const AXmlFile: string): string;
var
  Parts: TArray<string>;
  Argument, Name, Dropped, Run: string;
  Drop: Boolean;
begin
  Parts := nil;
  for Argument in SplitArguments(AExisting) do
  begin
    Name := OptionName(Argument);
    Drop := False;
    for Dropped in DroppedOptions do
      if Name = Dropped then
        Drop := True;
    if not Drop then
      Parts := Parts + [Argument];
  end;
  Run := '';
  for Name in ANames do
    if Name <> '' then
    begin
      if Run <> '' then
        Run := Run + ',';
      Run := Run + Name;
    end;
  if Run <> '' then
    Parts := Parts + [QuoteArgument('--run:' + Run)];
  Parts := Parts + ['--exitbehavior:Continue'];
  if AXmlFile <> '' then
    Parts := Parts + [QuoteArgument('--xmlfile:' + AXmlFile)];
  Result := string.Join(' ', Parts);
end;

class function TAtlasTestDebug.DebugWanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := RunWanted(ASettings) and ASettings.TestDebug;
end;

class function TAtlasTestDebug.RunWanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.TestRun and ASettings.CodeLensTests;
end;

class function TAtlasTestDebug.LensWanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.CodeLensTests and ASettings.TestRun;
end;

class function TAtlasTestDebug.LensDebugWanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := LensWanted(ASettings) and DebugWanted(ASettings);
end;

class function TAtlasTestDebug.BreakWanted(const ASettings: TAtlasPluginSettings;
  const ASelection: TAtlasTestSelection): Boolean;
begin
  Result := ASettings.TestBreakAtStart and (ASelection.Method <> '') and (ASelection.BreakLine >= 0);
end;

end.
