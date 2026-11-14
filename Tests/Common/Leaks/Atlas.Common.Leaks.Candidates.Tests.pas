unit Atlas.Common.Leaks.Candidates.Tests;

// Tests für die Kandidaten eines Leckberichts (#1875): Stellen „TKlasse.Create…“
// finden und bewerten (nie freigegeben, Rückgabe, Argument, Feld frei im
// Destruktor, Owner, lokal frei, nicht im Programm), Kopfzeilen, raise,
// Kommentare und Strings übergehen, Reihenfolge über mehrere Dateien.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Leaks.Candidates;

type
  [TestFixture]
  TLeakCandidatesTests = class
  private
    function Only(const AText, AClassName: string): TLeakCandidate;
  public
    [Test]
    procedure StatementNeverFreed;
    [Test]
    procedure LocalWithAndWithoutFree;
    [Test]
    procedure FieldFreedInDestructor;
    [Test]
    procedure FieldWithoutFree;
    [Test]
    procedure ReturnedToCaller;
    [Test]
    procedure PassedAsArgument;
    [Test]
    procedure OwnerInConstructor;
    [Test]
    procedure SkipsHeaderRaiseCommentsAndStrings;
    [Test]
    procedure QualifiedNameAndOtherConstructors;
    [Test]
    procedure FileOutsideProgram;
    [Test]
    procedure FindSortsByRatingThenFile;
    [Test]
    procedure ScanReadsUseTargetAndDestructorFrees;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Leaks.Internals.CreateScan;

const
  cNl = #13#10;

function SourceFile(const AName, AText: string; AInProgram: Boolean): TLeakSourceFile;
begin
  Result := Default(TLeakSourceFile);
  Result.FileName := AName;
  Result.Text := AText;
  Result.InProgram := AInProgram;
end;

function Body(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := 'unit U;' + cNl + 'interface' + cNl + 'implementation' + cNl;
  for mLine in ALines do
  begin
    Result := Result + mLine + cNl;
  end;
  Result := Result + 'end.' + cNl;
end;

function TLeakCandidatesTests.Only(const AText, AClassName: string): TLeakCandidate;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.InFile(SourceFile('U.pas', AText, True), TArray<string>.Create(AClassName));
  Assert.AreEqual(1, Integer(Length(mFound)), 'genau eine Stelle');
  Result := mFound[0];
end;

procedure TLeakCandidatesTests.StatementNeverFreed;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.InFile(SourceFile('U.pas', Body(['procedure Lade;', 'begin',
    '  TStringList.Create;', '  TStringList.Create.Add(''x'');', 'end;']), True), TArray<string>.Create('TStringList'));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual<TLeakRating>(TLeakRating.NeverFreed, mFound[0].Rating);
  Assert.AreEqual<TLeakRating>(TLeakRating.NeverFreed, mFound[1].Rating, 'verkettet');
  Assert.AreEqual(5, mFound[0].Position.Line);
  Assert.AreEqual(2, mFound[0].Position.Character);
  Assert.AreEqual('Lade', mFound[0].Routine);
end;

procedure TLeakCandidatesTests.LocalWithAndWithoutFree;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.InFile(SourceFile('U.pas', Body(['procedure TForm1.Lade;', 'var L: TStringList;',
    'begin', '  L := TStringList.Create;', '  try', '  finally', '    L.Free;', '  end;', 'end;', '',
    'procedure TForm1.Speichere;', 'var L: TStringList;', 'begin', '  L := TStringList.Create;', 'end;']), True),
    TArray<string>.Create('TStringList'));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual<TLeakRating>(TLeakRating.LocalFreed, mFound[0].Rating);
  Assert.AreEqual('L', mFound[0].Target);
  Assert.AreEqual('TForm1.Lade', mFound[0].Routine);
  Assert.AreEqual<TLeakRating>(TLeakRating.NeverFreed, mFound[1].Rating, 'Free steht in einer anderen Routine');
end;

procedure TLeakCandidatesTests.FieldFreedInDestructor;
begin
  Assert.AreEqual<TLeakRating>(TLeakRating.FieldFreed,
    Only(Body(['constructor TListe.Create;', 'begin', '  FItems := TStringList.Create;', 'end;',
    'destructor TListe.Destroy;', 'begin', '  FreeAndNil(FItems);', '  inherited;', 'end;']),
    'TStringList').Rating);
  Assert.AreEqual<TLeakRating>(TLeakRating.FieldFreed,
    Only(Body(['constructor TListe.Create;', 'begin', '  Self.Items := TStringList.Create;', 'end;',
    'destructor TListe.Destroy;', 'begin', '  Items.Free;', 'end;']), 'TStringList').Rating,
    'Self.X gilt als Feld');
end;

procedure TLeakCandidatesTests.FieldWithoutFree;
var
  mCandidate: TLeakCandidate;
begin
  mCandidate := Only(Body(['constructor TListe.Create;', 'begin', '  FItems := TStringList.Create;', 'end;',
    'destructor TListe.Destroy;', 'begin', '  FAndere.Free;', 'end;']), 'TStringList');
  Assert.AreEqual<TLeakRating>(TLeakRating.NeverFreed, mCandidate.Rating);
  Assert.AreEqual('FItems', mCandidate.Target);
end;

procedure TLeakCandidatesTests.ReturnedToCaller;
begin
  Assert.AreEqual<TLeakRating>(TLeakRating.Returned,
    Only(Body(['function Neu: TKunde;', 'begin', '  Result := TKunde.Create;', 'end;']),
    'TKunde').Rating);
  Assert.AreEqual<TLeakRating>(TLeakRating.Returned,
    Only(Body(['function Neu: TKunde;', 'begin', '  Exit(TKunde.Create);', 'end;']),
    'TKunde').Rating, 'Exit(…)');
  Assert.AreEqual<TLeakRating>(TLeakRating.Returned,
    Only(Body(['function Neu: TKunde;', 'var K: TKunde;', 'begin', '  K := TKunde.Create;',
    '  K.Name := ''x'';', '  Result := K;', 'end;']), 'TKunde').Rating, 'über Variable');
end;

procedure TLeakCandidatesTests.PassedAsArgument;
begin
  Assert.AreEqual<TLeakRating>(TLeakRating.Passed, Only(Body(['procedure Fuelle(AListe: TObjectList);', 'begin',
    '  AListe.Add(TKunde.Create);', 'end;']), 'TKunde').Rating);
  Assert.AreEqual<TLeakRating>(TLeakRating.Passed,
    Only(Body(['procedure Fuelle;', 'begin', '  Merke(1, TKunde.Create);', 'end;']),
    'TKunde').Rating, 'zweites Argument');
end;

procedure TLeakCandidatesTests.OwnerInConstructor;
begin
  Assert.AreEqual<TLeakRating>(TLeakRating.Owned,
    Only(Body(['procedure TForm1.Baue;', 'begin', '  FKnopf := TButton.Create(Self);', 'end;']),
    'TButton').Rating);
  Assert.AreEqual<TLeakRating>(TLeakRating.Owned,
    Only(Body(['procedure Baue(AOwner: TComponent);', 'begin', '  TButton.Create(AOwner);', 'end;']),
    'TButton').Rating);
  Assert.AreEqual<TLeakRating>(TLeakRating.NeverFreed,
    Only(Body(['procedure Baue;', 'begin', '  TButton.Create(nil);', 'end;']),
    'TButton').Rating, 'nil ist kein Owner');
end;

procedure TLeakCandidatesTests.SkipsHeaderRaiseCommentsAndStrings;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.InFile(SourceFile('U.pas', Body(['constructor TKunde.Create;', 'begin',
    '  // TKunde.Create;', '  { TKunde.Create; }', '  Log(''TKunde.Create'');', '  raise TKunde.Create;', 'end;']),
    True), TArray<string>.Create('TKunde'));
  Assert.AreEqual(0, Integer(Length(mFound)));
end;

procedure TLeakCandidatesTests.QualifiedNameAndOtherConstructors;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.InFile(SourceFile('U.pas', Body(['procedure Lade;', 'begin',
    '  Classes.TStringList.Create;', '  TKunde.CreateNamed(''x'');', '  TKunde.Load;', 'end;']), True),
    TArray<string>.Create('tstringlist', 'TKunde'));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('TStringList', mFound[0].ClassName);
  Assert.AreEqual('TKunde', mFound[1].ClassName);
end;

procedure TLeakCandidatesTests.FileOutsideProgram;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.InFile(SourceFile('Kunde.Tests.pas', Body(['procedure Test;', 'begin',
    '  TKunde.Create;', 'end;']), False), TArray<string>.Create('TKunde'));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual<TLeakRating>(TLeakRating.NotInProgram, mFound[0].Rating);
end;

procedure TLeakCandidatesTests.FindSortsByRatingThenFile;
var
  mFound: TArray<TLeakCandidate>;
begin
  mFound := TLeakCandidates.Find([SourceFile('B.pas', Body(['procedure P;', 'begin', '  TKunde.Create;',
    'end;']), True), SourceFile('A.pas', Body(['function F: TKunde;', 'begin', '  Result := TKunde.Create;',
    'end;', 'procedure Q;', 'begin', '  TKunde.Create;', 'end;']), True), SourceFile('C.pas', 'unit C; end.', True)],
    TArray<string>.Create('TKunde'));
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('A.pas', mFound[0].FileName);
  Assert.AreEqual<TLeakRating>(TLeakRating.NeverFreed, mFound[0].Rating);
  Assert.AreEqual('B.pas', mFound[1].FileName);
  Assert.AreEqual<TLeakRating>(TLeakRating.Returned, mFound[2].Rating);
end;

procedure TLeakCandidatesTests.ScanReadsUseTargetAndDestructorFrees;
var
  mScan: TLeakCreateScan;
begin
  mScan := TLeakCreateScan.Run(Body(['constructor TListe.Create;', 'begin', '  Self.FItems := TStringList.Create;',
    '  Merke(TStringList.Create);', 'end;', 'destructor TListe.Destroy;', 'begin', '  FreeAndNil(Self.FItems);',
    'end;']), TArray<string>.Create('TStringList'));
  Assert.AreEqual(2, Integer(Length(mScan.Sites)));
  Assert.AreEqual<TLeakCreateUse>(TLeakCreateUse.Assigned, mScan.Sites[0].Use);
  Assert.AreEqual('FItems', mScan.Sites[0].Target);
  Assert.IsTrue(mScan.Sites[0].TargetIsField);
  Assert.AreEqual('TListe.Create', mScan.Sites[0].Routine);
  Assert.AreEqual<TLeakCreateUse>(TLeakCreateUse.Argument, mScan.Sites[1].Use);
  Assert.IsTrue(mScan.DestructorFrees('fitems'), 'FreeAndNil(Self.X)');
  Assert.IsFalse(mScan.DestructorFrees('fandere'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLeakCandidatesTests);

end.
