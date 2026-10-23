unit Atlas.UI.Architecture.Frame.Tests;

// Fenster „Atlas-Architektur“ (#1118), Fensterinhalt: Tabellen und Bäume aus
// den Daten des Servers, Sortieren per Spaltenklick, Filter, Öffnen von Unit
// und uses-Eintrag, Hinweise, Umfang und Bibliotheks-Units, Treffer der
// Karte.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Architecture.Frame;

type
  [TestFixture]
  TAtlasArchitectureFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasArchitectureFrame;
    FOpened: string;
    FLine: Integer;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FillsTablesAndTrees;
    [Test]
    procedure SortsByColumnClick;
    [Test]
    procedure FilterNarrowsEverything;
    [Test]
    procedure OpensUnitAndUsesEntry;
    [Test]
    procedure MessageScopeAndLibrary;
    [Test]
    procedure MapSelectsUnitUnderMouse;
    [Test]
    procedure PathCyclesAndSubsystems;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.Model.Tests;

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join(#10, ALines);
end;

procedure TAtlasArchitectureFrameTests.SetUp;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 600;
  FFrame := TAtlasArchitectureFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FFrame.OnOpenUnit :=
    procedure(AFileName: string)
    begin
      FOpened := AFileName;
      FLine := 0;
    end;
  FFrame.OnOpenLocation :=
    procedure(AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled);
  FFrame.SetModel(Model);
end;

procedure TAtlasArchitectureFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
  FOpened := '';
end;

procedure TAtlasArchitectureFrameTests.FillsTablesAndTrees;
begin
  Assert.AreEqual(3, Integer(Length(FFrame.CentralText)));
  Assert.IsTrue(Length(FFrame.SubsystemText) >= 7, 'Teilsysteme und ihre sechs Units');
  // Zyklus mit Weg und seinen beiden uses-Einträgen.
  Assert.AreEqual(3, Integer(Length(FFrame.CycleText)));
  Assert.IsTrue(StartsStr(TAtlasStrings.Text(TAtlasTextId.ArchitectureCycleImplementation), FFrame.CycleText[0]));
  Assert.IsTrue(Pos('App.Data.Cache', Joined(FFrame.CycleText)) > 0);
  Assert.IsTrue(Pos(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureStatus, [6, Length(FFrame.Model.Subsystems), 1,
    Length(FFrame.Model.CrossLinks), Integer(FFrame.Model.Generation and $7FFFFFFF), FFrame.Model.DurationMs]),
    FFrame.StatusLabel.Caption) = 1);
  // Aktive Ausschlüsse stehen in der Statuszeile.
  Assert.IsTrue(Pos('Tests/**', FFrame.StatusLabel.Caption) > 0);
  Assert.IsTrue(FFrame.SaveButton.Enabled);
end;

procedure TAtlasArchitectureFrameTests.SortsByColumnClick;
var
  Lines: TArray<string>;
begin
  // Vorgabe: gesamt abhängig, die größten zuerst.
  Lines := FFrame.CentralText;
  Assert.IsTrue(StrToInt(Lines[0].Split([#9])[3]) >= StrToInt(Lines[1].Split([#9])[3]));
  FFrame.CentralList.OnColumnClick(FFrame.CentralList, FFrame.CentralList.Columns[0]);
  Assert.IsTrue(FFrame.SortColumn = TAtlasArchColumn.Name);
  Assert.IsFalse(FFrame.SortDescending);
  Lines := FFrame.CentralText;
  Assert.IsTrue(CompareText(Lines[0].Split([#9])[0], Lines[1].Split([#9])[0]) < 0);
  FFrame.CentralList.OnColumnClick(FFrame.CentralList, FFrame.CentralList.Columns[0]);
  Assert.IsTrue(FFrame.SortDescending);
  Lines := FFrame.CentralText;
  Assert.IsTrue(CompareText(Lines[0].Split([#9])[0], Lines[1].Split([#9])[0]) > 0);
end;

procedure TAtlasArchitectureFrameTests.FilterNarrowsEverything;
begin
  FFrame.Filter.Text := 'cache';
  Assert.AreEqual('cache', FFrame.Map.Filter);
  Assert.IsTrue(Pos('App.Data.Cache', Joined(FFrame.SubsystemText)) > 0);
  Assert.AreEqual(0, Pos('App.Ui.Form', Joined(FFrame.SubsystemText)));
  Assert.AreEqual(3, Integer(Length(FFrame.CycleText)), 'der Zyklus enthält App.Data.Cache');
  FFrame.Filter.Text := 'ui form';
  Assert.AreEqual(0, Integer(Length(FFrame.CycleText)));
  FFrame.Filter.Text := '';
end;

procedure TAtlasArchitectureFrameTests.OpensUnitAndUsesEntry;
var
  Unit_: Integer;
begin
  Unit_ := FFrame.Model.IndexOf('App.Data.Db');
  FFrame.OpenUnit(Unit_);
  Assert.IsTrue(EndsText('Db.pas', FOpened));
  Assert.IsTrue(StartsText('C:\Projekt', FOpened));
  Assert.AreEqual(0, FLine);
  // uses-Eintrag ohne Fundstelle (kein Quelltext im Test): die Unit, in der er steht.
  FOpened := '';
  FFrame.OpenLink(FFrame.Model.Cycles[0].Edges[0]);
  Assert.IsTrue(EndsText('.pas', FOpened));
end;

procedure TAtlasArchitectureFrameTests.MessageScopeAndLibrary;
var
  Scope: string;
  Library_: Boolean;
begin
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureLoading), True);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ArchitectureLoading), FFrame.StatusLabel.Caption);
  Assert.IsTrue(FFrame.HasModel, 'bisherige Daten bleiben');
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoProject), False);
  Assert.IsFalse(FFrame.HasModel);
  Assert.AreEqual(0, Integer(Length(FFrame.CentralText)));
  Assert.IsFalse(FFrame.SaveButton.Enabled);
  Scope := '';
  FFrame.OnScopeChanged :=
    procedure(AScope: string)
    begin
      Scope := AScope;
    end;
  FFrame.ScopeValue := 'project';
  Assert.AreEqual('', Scope, 'Setzen von außen meldet nichts');
  Assert.AreEqual('project', FFrame.ScopeValue);
  Library_ := False;
  FFrame.OnLibraryChanged :=
    procedure(AValue: Boolean)
    begin
      Library_ := AValue;
    end;
  FFrame.IncludeLibrary := True;
  Assert.IsFalse(Library_, 'Setzen von außen meldet nichts');
  FFrame.LibraryCheck.Checked := False;
  Assert.IsFalse(FFrame.IncludeLibrary);
  FFrame.OnScopeChanged := nil;
  FFrame.OnLibraryChanged := nil;
end;

procedure TAtlasArchitectureFrameTests.MapSelectsUnitUnderMouse;
var
  Unit_: Integer;
  Fitted: Double;
begin
  FFrame.Map.FitView;
  Fitted := FFrame.Map.View.Scale;
  Unit_ := FFrame.Model.IndexOf('App.Main');
  Assert.AreEqual(Unit_, FFrame.Map.View.UnitAt(FFrame.Map.Model, FFrame.Map.View.ScreenX(FFrame.Model.Units[Unit_].X),
    FFrame.Map.View.ScreenY(FFrame.Model.Units[Unit_].Y)));
  FFrame.Map.SelectUnit(Unit_, True);
  Assert.AreEqual(Unit_, FFrame.Map.Selected);
  Assert.AreEqual(Double(FFrame.Map.ClientWidth / 2), FFrame.Map.View.ScreenX(FFrame.Model.Units[Unit_].X), 0.5);
  FFrame.Map.SelectUnit(99, False);
  Assert.AreEqual(-1, FFrame.Map.Selected);
  // „Namen“ blendet die Beschriftungen aus, „Einpassen“ holt die Karte zurück.
  FFrame.NamesCheck.Checked := False;
  Assert.IsFalse(FFrame.Map.ShowNames);
  FFrame.NamesCheck.Checked := True;
  Assert.IsTrue(FFrame.Map.ShowNames);
  FFrame.Map.ZoomBy(4);
  FFrame.FitButton.Click;
  Assert.AreEqual(Fitted, FFrame.Map.View.Scale, 0.0001, 'nach dem Einpassen wieder der Maßstab vom Anfang');
end;

procedure TAtlasArchitectureFrameTests.PathCyclesAndSubsystems;
var
  Main, Cache, Db: Integer;
begin
  Main := FFrame.Model.IndexOf('App.Main');
  Cache := FFrame.Model.IndexOf('App.Data.Cache');
  Db := FFrame.Model.IndexOf('App.Data.Db');
  // Weg wie in der HTML-Karte; die Zeile unter der Karte nennt ihn.
  Assert.IsTrue(FFrame.Map.ShowPath(Main, Cache));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitecturePath, [3,
    'App.Main → App.Data → App.Data.Db → App.Data.Cache']), FFrame.InfoLabel.Caption);
  Assert.IsFalse(FFrame.Map.ShowPath(Cache, Main));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureNoPath, ['App.Data.Cache', 'App.Main']),
    FFrame.InfoLabel.Caption);
  // Ohne implementation-uses gibt es Cache → Db nicht mehr; der Weg wird neu gesucht.
  Assert.IsTrue(FFrame.Map.ShowPath(Cache, Db));
  FFrame.ImplementationCheck.Checked := False;
  Assert.IsFalse(FFrame.Map.ShowImplementation);
  Assert.IsFalse(FFrame.Map.PathFound);
  FFrame.ImplementationCheck.Checked := True;
  Assert.IsTrue(FFrame.Map.PathFound);
  // Esc hebt den Weg auf, danach wieder der Hinweis.
  FFrame.Map.ClearPath;
  Assert.AreEqual(-1, FFrame.Map.PathFrom);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ArchitectureMapHint), FFrame.InfoLabel.Caption);
  FFrame.Map.ClearPath;
  Assert.AreEqual(-1, FFrame.Map.PathTo, 'zweimal aufheben schadet nicht');
  // Zyklen markieren.
  Assert.IsFalse(FFrame.Map.MarkCycles);
  FFrame.MarkCyclesCheck.Checked := True;
  Assert.IsTrue(FFrame.Map.MarkCycles);
  // Teilsysteme aus- und einblenden über das Menü.
  FFrame.FillSubsystemsMenu;
  Assert.AreEqual(Integer(Length(FFrame.Model.Subsystems)) + 2, FFrame.SubsystemsMenu.Items.Count);
  FFrame.SubsystemsMenu.Items[FFrame.Model.Units[Cache].Subsystem].Click;
  Assert.IsFalse(FFrame.Map.SubsystemVisible[FFrame.Model.Units[Cache].Subsystem]);
  Assert.IsFalse(FFrame.SubsystemsMenu.Items[FFrame.Model.Units[Cache].Subsystem].Checked);
  Assert.IsFalse(FFrame.Map.ShowPath(Main, Cache), 'Units ausgeblendeter Teilsysteme sind kein Ziel');
  FFrame.SubsystemsMenu.Items[FFrame.SubsystemsMenu.Items.Count - 1].Click;
  Assert.IsTrue(FFrame.Map.SubsystemVisible[FFrame.Model.Units[Cache].Subsystem]);
  Assert.IsTrue(FFrame.Map.PathFound, 'nach dem Einblenden wird der Weg neu gesucht');
  FFrame.Map.ClearPath;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureFrameTests);

end.
