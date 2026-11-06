unit Atlas.Core.Architecture.MapState.Tests;

// Zustand der Architekturkarte (#1118) ohne VCL: Weg über uses und fester Weg
// (#1117), Neusuche beim Ausblenden und beim Schalter implementation-uses,
// Auswahl über neue Daten, Filter und die Meldungen OnChange/OnPathChanged.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasArchitectureMapStateTests = class
  public
    [Test]
    procedure ShowsAndClearsShortestPath;
    [Test]
    procedure RecomputesPathWhenHidingOrSwitching;
    [Test]
    procedure RouteStaysWithoutImplementation;
    [Test]
    procedure NewModelKeepsSelectionByName;
    [Test]
    procedure FilterAndFlags;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.MapState,
  Atlas.Core.Architecture.Model.Tests;

type
  /// <summary>Zählt die Meldungen eines Zustands.</summary>
  TCounter = class
  public
    Changes: Integer;
    PathChanges: Integer;
  end;

function SampleModel: TAtlasArchitectureModel;
var
  mEnabled: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Result, mEnabled));
end;

function CountChange(ACounter: TCounter): TProc;
begin
  Result :=
    procedure
    begin
      Inc(ACounter.Changes);
    end;
end;

function CountPath(ACounter: TCounter): TProc;
begin
  Result :=
    procedure
    begin
      Inc(ACounter.PathChanges);
    end;
end;

procedure Watch(AState: TAtlasArchitectureMapState; ACounter: TCounter);
begin
  AState.OnChange := CountChange(ACounter);
  AState.OnPathChanged := CountPath(ACounter);
end;

procedure TAtlasArchitectureMapStateTests.ShowsAndClearsShortestPath;
var
  mState: TAtlasArchitectureMapState;
  mCounter: TCounter;
  mModel: TAtlasArchitectureModel;
  mMain, mCache: Integer;
begin
  mState := TAtlasArchitectureMapState.Create;
  mCounter := TCounter.Create;
  try
    mModel := SampleModel;
    mState.SetModel(mModel);
    Watch(mState, mCounter);
    mMain := mModel.IndexOf('App.Main');
    mCache := mModel.IndexOf('App.Data.Cache');
    Assert.IsTrue(mState.ShowPath(mMain, mCache));
    Assert.IsTrue(mState.Path.Shown);
    Assert.AreEqual(3, Integer(Length(mState.Path.Edges)));
    Assert.IsTrue(mState.Path.IsNode(mMain));
    Assert.IsTrue(mState.Path.IsNode(mCache));
    Assert.IsTrue(mState.Path.IsEdge(mState.Path.Edges[0]));
    Assert.IsTrue(mState.Highlighted(mCache));
    Assert.IsFalse(mState.Highlighted(mModel.IndexOf('App.Ui.Form')));
    Assert.AreEqual(1, mCounter.PathChanges);
    // Gegen die Richtung: Start und Ziel stehen, gefunden ist nichts.
    Assert.IsFalse(mState.ShowPath(mCache, mMain));
    Assert.AreEqual(mCache, mState.Path.From);
    Assert.IsFalse(mState.Path.Found);
    Assert.IsFalse(mState.Path.Shown);
    mState.ClearPath;
    Assert.AreEqual(-1, mState.Path.From);
    Assert.AreEqual(3, mCounter.PathChanges);
    // Ohne Weg meldet ClearPath nichts.
    mState.ClearPath;
    Assert.AreEqual(3, mCounter.PathChanges);
    // Ungültige Units heben den Weg auf.
    Assert.IsFalse(mState.ShowPath(-1, mCache));
    Assert.AreEqual(-1, mState.Path.From);
  finally
    mCounter.Free;
    mState.Free;
  end;
end;

procedure TAtlasArchitectureMapStateTests.RecomputesPathWhenHidingOrSwitching;
var
  mState: TAtlasArchitectureMapState;
  mCounter: TCounter;
  mModel: TAtlasArchitectureModel;
  mCache, mDb: Integer;
begin
  mState := TAtlasArchitectureMapState.Create;
  mCounter := TCounter.Create;
  try
    mModel := SampleModel;
    mState.SetModel(mModel);
    Watch(mState, mCounter);
    mCache := mModel.IndexOf('App.Data.Cache');
    mDb := mModel.IndexOf('App.Data.Db');
    // Cache → Db geht nur über implementation.
    Assert.IsTrue(mState.ShowPath(mCache, mDb));
    mState.SetFlag(TAtlasArchMapFlag.ShowImplementation, False);
    Assert.IsFalse(mState.Has(TAtlasArchMapFlag.ShowImplementation));
    Assert.IsFalse(mState.Path.Found);
    Assert.AreEqual(2, mCounter.PathChanges);
    mState.SetFlag(TAtlasArchMapFlag.ShowImplementation, True);
    Assert.IsTrue(mState.Path.Found);
    // Ausgeblendet: Units des Teilsystems sind unsichtbar, der Weg wird ohne sie gesucht.
    mState.SubsystemVisible[mModel.Units[mDb].Subsystem] := False;
    Assert.IsFalse(mState.SubsystemVisible[mModel.Units[mDb].Subsystem]);
    Assert.IsFalse(mState.UnitVisible(mDb));
    Assert.IsFalse(mState.Path.Found);
    Assert.AreEqual(4, mCounter.PathChanges);
    mState.ShowAllSubsystems;
    Assert.IsTrue(mState.UnitVisible(mDb));
    Assert.IsTrue(mState.Path.Found);
  finally
    mCounter.Free;
    mState.Free;
  end;
end;

procedure TAtlasArchitectureMapStateTests.RouteStaysWithoutImplementation;
var
  mState: TAtlasArchitectureMapState;
  mModel: TAtlasArchitectureModel;
  mUnits, mEdges: TArray<Integer>;
  mCache, mDb: Integer;
begin
  mState := TAtlasArchitectureMapState.Create;
  try
    mModel := SampleModel;
    mState.SetModel(mModel);
    Assert.IsTrue(mModel.RouteOf(TArray<string>.Create('App.Data.Cache', 'App.Data.Db'), mUnits, mEdges));
    mCache := mModel.IndexOf('App.Data.Cache');
    mDb := mModel.IndexOf('App.Data.Db');
    // Ein ausgeblendetes Teilsystem des Wegs wird wieder eingeblendet.
    mState.SubsystemVisible[mModel.Units[mDb].Subsystem] := False;
    mState.ShowRoute(mUnits, mEdges);
    Assert.IsTrue(mState.UnitVisible(mDb));
    Assert.AreEqual(mCache, mState.Path.From);
    Assert.AreEqual(mDb, mState.Path.To_);
    Assert.AreEqual(2, Integer(Length(mState.Path.Route)));
    mState.SetFlag(TAtlasArchMapFlag.ShowImplementation, False);
    Assert.IsTrue(mState.Path.Shown);
    Assert.IsTrue(mState.Path.IsNode(mDb));
    // Eine einzelne Unit ist auch ein Weg.
    mState.ShowRoute(TArray<Integer>.Create(mDb), nil);
    Assert.IsTrue(mState.Path.Shown);
    // Ungültige Angaben heben ihn auf.
    mState.ShowRoute(TArray<Integer>.Create(Length(mModel.Units)), nil);
    Assert.AreEqual(-1, mState.Path.From);
    mState.ShowRoute(nil, nil);
    Assert.AreEqual(-1, mState.Path.From);
  finally
    mState.Free;
  end;
end;

procedure TAtlasArchitectureMapStateTests.NewModelKeepsSelectionByName;
var
  mState: TAtlasArchitectureMapState;
  mCounter: TCounter;
  mModel: TAtlasArchitectureModel;
  mMain, mCache, mOther: Integer;
begin
  mState := TAtlasArchitectureMapState.Create;
  mCounter := TCounter.Create;
  try
    mModel := SampleModel;
    mState.SetModel(mModel);
    Watch(mState, mCounter);
    mMain := mModel.IndexOf('App.Main');
    mCache := mModel.IndexOf('App.Data.Cache');
    mState.SelectUnit(mMain);
    Assert.AreEqual(mMain, mState.Selected);
    mState.SelectUnit(Length(mModel.Units));
    Assert.AreEqual(-1, mState.Selected);
    mState.SelectUnit(mMain);
    mState.ShowPath(mMain, mCache);
    // Ein anderes Teilsystem als das der gewählten Unit ausblenden: Der Weg wird neu gesucht.
    mOther := (mModel.Units[mMain].Subsystem + 1) mod Length(mModel.Subsystems);
    Assert.AreNotEqual(mModel.Units[mMain].Subsystem, mOther);
    mState.SubsystemVisible[mOther] := False;
    mState.SetModel(mModel);
    Assert.AreEqual(mMain, mState.Selected);
    Assert.AreEqual(-1, mState.Path.From);
    Assert.IsTrue(mState.SubsystemVisible[mOther]);
    // Ein bestehender Weg meldet sein Ende.
    Assert.AreEqual(3, mCounter.PathChanges);
    Assert.IsTrue(mState.IsCentral(mModel.Central[0]));
    Assert.IsFalse(mState.IsAdded(0));
    Assert.IsFalse(mState.HasChanges);
  finally
    mCounter.Free;
    mState.Free;
  end;
end;

procedure TAtlasArchitectureMapStateTests.FilterAndFlags;
var
  mState: TAtlasArchitectureMapState;
  mCounter: TCounter;
  mModel: TAtlasArchitectureModel;
  mCycle: TAtlasArchEdge;
begin
  mState := TAtlasArchitectureMapState.Create;
  mCounter := TCounter.Create;
  try
    mModel := SampleModel;
    mState.SetModel(mModel);
    Watch(mState, mCounter);
    Assert.IsTrue(mState.Has(TAtlasArchMapFlag.ShowNames));
    Assert.IsFalse(mState.Has(TAtlasArchMapFlag.MarkCycles));
    Assert.IsTrue(mState.Highlighted(mModel.IndexOf('App.Ui.Form')));
    mState.Filter := 'Cache';
    Assert.AreEqual(1, mCounter.Changes);
    Assert.IsTrue(mState.Highlighted(mModel.IndexOf('App.Data.Cache')));
    Assert.IsFalse(mState.Highlighted(mModel.IndexOf('App.Ui.Form')));
    // Gleicher Wert: keine Meldung.
    mState.Filter := 'Cache';
    mState.SetFlag(TAtlasArchMapFlag.ShowNames, True);
    Assert.AreEqual(1, mCounter.Changes);
    mCycle := Default(TAtlasArchEdge);
    mCycle.Source := mModel.Cycles[0].Edges[0].Source;
    mCycle.Target := mModel.Cycles[0].Edges[0].Target;
    Assert.IsFalse(mState.MarksCycle(mCycle));
    mState.SetFlag(TAtlasArchMapFlag.MarkCycles, True);
    Assert.IsTrue(mState.MarksCycle(mCycle));
    Assert.AreEqual(2, mCounter.Changes);
    mState.SetHover(0);
    Assert.AreEqual(0, mState.Hover);
  finally
    mCounter.Free;
    mState.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureMapStateTests);

end.
