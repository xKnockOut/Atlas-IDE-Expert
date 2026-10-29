unit Atlas.Common.Lsp.Hotspots.Tests;

// Tests von atlas/hotspots und den Befehlen atlas.hotspots und
// atlas.hotspots.saveReport (#1354): ausgeschaltet, ohne
// Versionsverwaltung (Grund statt leerer Liste), Rechnung im Hintergrund mit
// "pending", Ergebnis bis zum nächsten Commit, "refresh", Fehler einmal,
// Bericht auf der gewählten Ebene und die Prüfung der Optionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspHotspotsTests = class
  public
    [Test]
    procedure DisabledAnswersEnabledFalse;
    [Test]
    procedure WithoutVcsAnswersReason;
    [Test]
    procedure ComputesInBackgroundUntilNextCommit;
    [Test]
    procedure RefreshComputesAgain;
    [Test]
    procedure UnknownHeadComputesForEachRequest;
    [Test]
    procedure ReportsVcsErrorOnce;
    [Test]
    procedure TextFormatAndLimit;
    [Test]
    procedure SaveReportUsesChosenLevel;
    [Test]
    procedure RejectsInvalidOptions;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Lsp.Hotspots,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Hotspots.Service.Tests;

type
  /// <summary>Server-Teil für die Tests: Index mit zwei Units, Texte, Versionsverwaltung im Speicher.</summary>
  TFixture = class
  private
    FIndex: ISymbolIndex;
    FService: THotspotService;
    FHotspots: TLspHotspots;
    FVcs: THotspotFakeVcs;
    FVcsRef: IHotspotVcs;
    FSettings: TServerSettings;
    FNoVcs: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Anfrage mit params AJson; der Aufrufer gibt die Antwort frei.</summary>
    function Ask(const AJson: string): TJSONObject;
    property Hotspots: TLspHotspots read FHotspots;
    property Vcs: THotspotFakeVcs read FVcs;
    property Settings: TServerSettings read FSettings write FSettings;
    property NoVcs: Boolean read FNoVcs write FNoVcs;
  end;

function ReadText(const AFileName: string; out AText: string): Boolean;
var
  mName: string;
begin
  // Pfade wie UsesUnit (C:\Projekt\A.pas), auch unter Linux.
  mName := Copy(AFileName, LastDelimiter('\/', AFileName) + 1, MaxInt);
  AText := HotspotUnitText(ChangeFileExt(mName, ''), 4);
  Result := True;
end;

constructor TFixture.Create;
begin
  inherited Create;
  FSettings := TServerSettings.Default;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(UsesUnit('A', nil, nil));
  FIndex.AddUnit(UsesUnit('B', nil, nil));
  FVcs := THotspotFakeVcs.Create(THotspotVcsKind.Git, 'C:\Projekt');
  FVcsRef := FVcs;
  FVcs.AddCommit('c2', 'anna', IncDay(Now, -1), ['A.pas', 'B.pas']);
  FVcs.AddCommit('c1', 'anna', IncDay(Now, -2), ['A.pas']);
  FService := THotspotService.Create(FIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadText(AFileName, AText);
    end);
  FHotspots := TLspHotspots.Create(FService,
    function(const AFileName: string; out ARequest: THotspotRequest; out ASettings: TServerSettings;
      out AVcs: IHotspotVcs; out AError: string): Boolean
    begin
      ASettings := FSettings;
      ARequest := THotspotRequest.FromSettings(FSettings);
      ARequest.Title := 'Projekt';
      ARequest.Root := 'C:\Projekt';
      AError := '';
      AVcs := nil;
      if FNoVcs then
        AError := 'Keine Arbeitskopie (vcs.provider = auto)'
      else
        AVcs := FVcsRef;
      Result := True;
    end);
end;

destructor TFixture.Destroy;
begin
  FHotspots.Free;
  FService.Free;
  FVcsRef := nil;
  FIndex := nil;
  inherited Destroy;
end;

function TFixture.Ask(const AJson: string): TJSONObject;
var
  mParams, mAnswer: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue(AJson);
  try
    mAnswer := FHotspots.Request(mParams);
  finally
    mParams.Free;
  end;
  Result := mAnswer as TJSONObject;
end;

function Flag(const AObject: TJSONObject; const AName: string): Boolean;
begin
  Result := (AObject.GetValue(AName) is TJSONBool) and TJSONBool(AObject.GetValue(AName)).AsBoolean;
end;

{ TLspHotspotsTests }

procedure TLspHotspotsTests.DisabledAnswersEnabledFalse;
var
  mFixture: TFixture;
  mSettings: TServerSettings;
  mAnswer: TJSONObject;
begin
  mFixture := TFixture.Create;
  try
    mSettings := mFixture.Settings;
    mSettings.HotspotsEnabled := False;
    mFixture.Settings := mSettings;
    mAnswer := mFixture.Ask('{}');
    try
      Assert.IsFalse(Flag(mAnswer, 'enabled'));
      Assert.AreEqual(1, mAnswer.Count);
    finally
      mAnswer.Free;
    end;
    Assert.AreEqual(0, mFixture.Hotspots.Jobs);
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.WithoutVcsAnswersReason;
var
  mFixture: TFixture;
  mAnswer: TJSONObject;
begin
  mFixture := TFixture.Create;
  try
    mFixture.NoVcs := True;
    mAnswer := mFixture.Ask('{}');
    try
      Assert.IsTrue(Flag(mAnswer, 'enabled'));
      Assert.IsFalse(Flag(mAnswer, 'vcs'));
      Assert.AreEqual('Keine Arbeitskopie (vcs.provider = auto)', mAnswer.GetValue('message').Value);
      Assert.IsNull(mAnswer.GetValue('data'), 'keine leere Liste');
    finally
      mAnswer.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.ComputesInBackgroundUntilNextCommit;
var
  mFixture: TFixture;
  mAnswer: TJSONObject;
  mData: TJSONObject;
begin
  mFixture := TFixture.Create;
  try
    mAnswer := mFixture.Ask('{"level":"method"}');
    try
      Assert.IsTrue(Flag(mAnswer, 'pending'), 'erste Anfrage wartet nicht');
      Assert.AreEqual('C:\Projekt', mAnswer.GetValue('root').Value);
    finally
      mAnswer.Free;
    end;
    mFixture.Hotspots.WaitIdle;
    mAnswer := mFixture.Ask('{"level":"method"}');
    try
      Assert.IsFalse(Flag(mAnswer, 'pending'));
      Assert.AreEqual('json', mAnswer.GetValue('format').Value);
      mData := mAnswer.GetValue('data') as TJSONObject;
      Assert.AreEqual('method', mData.GetValue('level').Value);
      Assert.AreEqual(2, (mData.GetValue('units') as TJSONArray).Count);
      Assert.AreEqual(2, (mData.GetValue('methods') as TJSONArray).Count);
    finally
      mAnswer.Free;
    end;
    mAnswer := mFixture.Ask('{"level":"method"}');
    mAnswer.Free;
    Assert.AreEqual(1, mFixture.Hotspots.Jobs, 'gleicher Stand: kein neuer Lauf');
    mFixture.Vcs.HeadValue := 'h2';
    mAnswer := mFixture.Ask('{"level":"method"}');
    try
      Assert.IsTrue(Flag(mAnswer, 'pending'), 'neuer Commit');
    finally
      mAnswer.Free;
    end;
    mFixture.Hotspots.WaitIdle;
    Assert.AreEqual(2, mFixture.Hotspots.Jobs);
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.RefreshComputesAgain;
var
  mFixture: TFixture;
  mAnswer: TJSONObject;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Ask('{}').Free;
    mFixture.Hotspots.WaitIdle;
    mAnswer := mFixture.Ask('{"refresh":true}');
    try
      Assert.IsTrue(Flag(mAnswer, 'pending'), '„Neu berechnen“');
    finally
      mAnswer.Free;
    end;
    mFixture.Hotspots.WaitIdle;
    Assert.AreEqual(2, mFixture.Hotspots.Jobs);
    mAnswer := mFixture.Ask('{}');
    try
      Assert.IsNotNull(mAnswer.GetValue('data'));
    finally
      mAnswer.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.UnknownHeadComputesForEachRequest;
var
  mFixture: TFixture;
  mAnswer: TJSONObject;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Vcs.HeadValue := '';
    mFixture.Ask('{}').Free;
    mFixture.Hotspots.WaitIdle;
    mAnswer := mFixture.Ask('{}');
    try
      Assert.IsNotNull(mAnswer.GetValue('data'), 'Ergebnis gilt für diese Anfrage');
    finally
      mAnswer.Free;
    end;
    mAnswer := mFixture.Ask('{}');
    try
      Assert.IsTrue(Flag(mAnswer, 'pending'), 'ohne Stand nicht wiederverwendet');
    finally
      mAnswer.Free;
    end;
    mFixture.Hotspots.WaitIdle;
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.ReportsVcsErrorOnce;
var
  mFixture: TFixture;
  mAnswer: TJSONObject;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Vcs.LogError := 'git log ist gescheitert (Exit-Code 128)';
    mFixture.Ask('{}').Free;
    mFixture.Hotspots.WaitIdle;
    Assert.WillRaise(
      procedure
      begin
        mFixture.Ask('{}').Free;
      end, EJsonRpcError);
    mFixture.Vcs.LogError := '';
    mAnswer := mFixture.Ask('{}');
    try
      Assert.IsTrue(Flag(mAnswer, 'pending'), 'nach dem Fehler wird neu gerechnet');
    finally
      mAnswer.Free;
    end;
    mFixture.Hotspots.WaitIdle;
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.TextFormatAndLimit;
var
  mFixture: TFixture;
  mAnswer: TJSONObject;
  mText: string;
begin
  mFixture := TFixture.Create;
  try
    mFixture.Ask('{"format":"text","limit":1}').Free;
    mFixture.Hotspots.WaitIdle;
    mAnswer := mFixture.Ask('{"format":"text","limit":1}');
    try
      Assert.AreEqual('text', mAnswer.GetValue('format').Value);
      mText := mAnswer.GetValue('text').Value;
      Assert.IsTrue(mText.Contains('1 von 2'), mText);
    finally
      mAnswer.Free;
    end;
    mAnswer := mFixture.Ask('{"format":"markdown"}');
    try
      Assert.IsTrue(mAnswer.GetValue('text').Value.StartsWith('# Hotspots Projekt'));
    finally
      mAnswer.Free;
    end;
  finally
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.SaveReportUsesChosenLevel;
var
  mFixture: TFixture;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
  mTarget, mText: string;
begin
  mFixture := TFixture.Create;
  mTarget := TPath.Combine(TPath.GetTempPath, 'AtlasHotspots-' + TGUID.NewGuid.ToString.Substring(1, 8) + '.md');
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('file:///C:/Projekt/Projekt.dproj');
    mArguments.Add(mTarget);
    mArguments.AddElement(TJSONObject.ParseJSONValue('{"level":"unit"}'));
    mAnswer := mFixture.Hotspots.SaveReport(mArguments);
    try
      Assert.IsTrue(Flag(mAnswer as TJSONObject, 'pending'));
    finally
      mAnswer.Free;
    end;
    mFixture.Hotspots.WaitIdle;
    mAnswer := mFixture.Hotspots.SaveReport(mArguments);
    try
      Assert.AreEqual(mTarget, (mAnswer as TJSONObject).GetValue('file').Value);
    finally
      mAnswer.Free;
    end;
    mText := TFile.ReadAllText(mTarget, TEncoding.UTF8);
    Assert.IsTrue(mText.Contains('## Units'));
    Assert.IsFalse(mText.Contains('## Methoden'), 'gewählte Ebene, obwohl auf Methodenebene gerechnet');
    Assert.AreEqual(1, mFixture.Hotspots.Jobs, 'dieselbe Rechnung wie das Fenster');
    mFixture.Ask('{"level":"method"}').Free;
    Assert.AreEqual(1, mFixture.Hotspots.Jobs, 'Fenster bekommt das Ergebnis des Berichts');
  finally
    mArguments.Free;
    if TFile.Exists(mTarget) then
      TFile.Delete(mTarget);
    mFixture.Free;
  end;
end;

procedure TLspHotspotsTests.RejectsInvalidOptions;
var
  mFixture: TFixture;
  mRequest: THotspotRequest;
  mError: string;
  mParams: TJSONObject;
  mResult: THotspotResult;
begin
  mFixture := TFixture.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        mFixture.Ask('{"format":"pdf"}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        mFixture.Ask('{"section":"trend"}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        mFixture.Ask('{"limit":-1}').Free;
      end, EJsonRpcError);
    Assert.WillRaise(
      procedure
      begin
        mFixture.Ask('{"level":"class"}').Free;
      end, EJsonRpcError);
    Assert.AreEqual(0, mFixture.Hotspots.Jobs);
  finally
    mFixture.Free;
  end;
  mRequest := THotspotRequest.FromSettings(TServerSettings.Default);
  mParams := TJSONObject.ParseJSONValue('{"months":61}') as TJSONObject;
  try
    Assert.IsFalse(TLspHotspots.ApplyOptions(mParams, mRequest, mError));
    Assert.IsTrue(mError.Contains('months'));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"months":3,"level":"method"}') as TJSONObject;
  try
    Assert.IsTrue(TLspHotspots.ApplyOptions(mParams, mRequest, mError));
    Assert.AreEqual(3, mRequest.Options.Months);
    Assert.IsTrue(mRequest.Level = THotspotLevel.Methods);
  finally
    mParams.Free;
  end;
  mResult := Default(THotspotResult);
  SetLength(mResult.Units, 5);
  SetLength(mResult.Coupling, 2);
  mResult := TLspHotspots.Limited(mResult, 3);
  Assert.AreEqual(3, Integer(Length(mResult.Units)));
  Assert.AreEqual(2, Integer(Length(mResult.Coupling)));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHotspotsTests);

end.
