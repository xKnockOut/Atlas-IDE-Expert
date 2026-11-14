unit Atlas.Common.Editing.ClassLayout.Tests;

// Tests für die gemeinsamen Bausteine der Klassenumbauten (#664, #713, #675,
// #717, #716): Klassenaufbau lesen (Kopf, Vorfahren, Mitglieder, Abschnitte,
// Rümpfe auch überladener Methoden, Verwendung), Änderungen (Mitglied und
// Feldgruppe löschen, einfügen, Vorfahren setzen, Rumpf kopieren) und der
// zeilenweise Vergleich zweier Texte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TClassLayoutTests = class
  public
    [Test]
    procedure ReadsHeader;
    [Test]
    procedure ReadsMembers;
    [Test]
    procedure FindsBodiesOfOverloads;
    [Test]
    procedure KnowsUses;
    [Test]
    procedure DeletesMemberWithBody;
    [Test]
    procedure DeletesNameOfFieldGroup;
    [Test]
    procedure InsertsFieldsBeforeMethods;
    [Test]
    procedure InsertsNewSection;
    [Test]
    procedure SetsAncestors;
    [Test]
    procedure CopiesBodyWithOtherClass;
    [Test]
    procedure DiffGivesLineEdits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.ClassLayout;

const
  cSource =
    'unit U;'#10 +                                                  // 0
    'interface'#10 +                                                // 1
    'type'#10 +                                                     // 2
    '  /// Kunde'#10 +                                              // 3
    '  [Attr]'#10 +                                                 // 4
    '  TKunde = class abstract(TBasis, IFoo)'#10 +                  // 5
    '  private'#10 +                                                // 6
    '    FA, FB: Integer;'#10 +                                     // 7
    '    function GetName: string;'#10 +                            // 8
    '  public'#10 +                                                 // 9
    '    /// Laden'#10 +                                            // 10
    '    procedure Load(AValue: Integer); overload; virtual;'#10 + // 11
    '    procedure Load(const AName: string); overload;'#10 +      // 12
    '    class function Make: TKunde;'#10 +                         // 13
    '    property Name: string read GetName write FB;'#10 +        // 14
    '  end;'#10 +                                                   // 15
    'implementation'#10 +                                           // 16
    #10 +                                                           // 17
    'function TKunde.GetName: string;'#10 +                         // 18
    'begin'#10 +                                                    // 19
    '  Result := IntToStr(FA);'#10 +                                // 20
    'end;'#10 +                                                     // 21
    #10 +                                                           // 22
    'procedure TKunde.Load(const AName: string);'#10 +              // 23
    'begin'#10 +                                                    // 24
    '  Self.Load(Length(AName));'#10 +                              // 25
    'end;'#10 +                                                     // 26
    #10 +                                                           // 27
    'procedure TKunde.Load(AValue: Integer);'#10 +                  // 28
    'begin'#10 +                                                    // 29
    '  FB := AValue + Other.FA;'#10 +                               // 30
    'end;'#10 +                                                     // 31
    #10 +                                                           // 32
    'class function TKunde.Make: TKunde;'#10 +                      // 33
    'begin'#10 +                                                    // 34
    '  Result := TKunde.Create;'#10 +                               // 35
    'end;'#10 +                                                     // 36
    #10 +                                                           // 37
    'end.';

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

type
  TLayoutProc = reference to procedure(ALayout: TClassLayout);

procedure WithLayout(const AText: string; const AProc: TLayoutProc);
var
  mTree: TSyntaxTree;
  mLayout: TClassLayout;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mLayout := TClassLayout.Read(mTree, AText, TClassLayout.DeclNamed(mTree, 'TKunde'));
    try
      AProc(mLayout);
    finally
      mLayout.Free;
    end;
  finally
    mTree.Free;
  end;
end;

{ TClassLayoutTests }

procedure TClassLayoutTests.ReadsHeader;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      Assert.AreEqual('TKunde', ALayout.Name);
      Assert.AreEqual(3, ALayout.FirstLine, 'mit Doku und Attribut');
      Assert.AreEqual(5, ALayout.HeaderLine);
      Assert.AreEqual(15, ALayout.EndLine);
      Assert.AreEqual(2, Integer(Length(ALayout.Ancestors)));
      Assert.AreEqual('TBasis', ALayout.Ancestors[0]);
      Assert.AreEqual('IFoo', ALayout.Ancestors[1]);
      Assert.IsTrue(ALayout.InInterface);
      Assert.AreEqual('  ', ALayout.Indent);
      Assert.AreEqual('    ', ALayout.MemberIndent);
      Assert.AreEqual(2, Integer(Length(ALayout.Sections)), 'der leere Abschnitt vor private zählt nicht');
    end);
end;

procedure TClassLayoutTests.ReadsMembers;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    var
      Name: TClassMember;
    begin
      Assert.AreEqual(7, Integer(Length(ALayout.Members)));
      Assert.AreEqual('FA', ALayout.Members[0].Name);
      Assert.AreEqual('FB', ALayout.Members[1].Name);
      Assert.IsTrue(ALayout.Members[1].IsFieldGroup);
      Assert.AreEqual('Integer', ALayout.Members[1].TypeName);
      Assert.AreEqual<TClassVisibility>(TClassVisibility.Private_, ALayout.Members[0].Visibility);
      Assert.AreEqual<TClassVisibility>(TClassVisibility.Public_, ALayout.Members[3].Visibility);
      Assert.AreEqual(10, ALayout.Members[3].FirstLine, 'mit Doku-Kommentar');
      Assert.AreEqual(10, ALayout.Members[3].DocLine);
      Assert.IsTrue(ALayout.Members[3].IsVirtual);
      Assert.IsTrue(ALayout.Members[3].HasDirective('overload'));
      Assert.IsTrue(ALayout.Members[5].IsClassMember);
      Assert.AreEqual('TKunde', ALayout.Members[5].TypeName);
      Name := ALayout.Members[6];
      Assert.AreEqual<TClassMemberKind>(TClassMemberKind.Property_, Name.Kind);
      Assert.AreEqual('GetName', Name.ReadAccessor);
      Assert.AreEqual('FB', Name.WriteAccessor);
      Assert.AreEqual('procedure Load(AValue: Integer);', ALayout.Head(3));
      Assert.AreEqual('procedure Load(AValue: Integer); overload; virtual;', ALayout.Declaration(3));
      Assert.AreEqual('FB: Integer;', ALayout.Declaration(1));
      Assert.AreEqual(1, Integer(Length(ALayout.DocLines(3))));
      Assert.AreEqual(3, ALayout.MemberAtLine(11));
    end);
end;

procedure TClassLayoutTests.FindsBodiesOfOverloads;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      Assert.AreEqual(18, ALayout.Members[2].BodyFirstLine);
      Assert.AreEqual(28, ALayout.Members[3].BodyFirstLine, 'Load(Integer)');
      Assert.AreEqual(23, ALayout.Members[4].BodyFirstLine, 'Load(string)');
      Assert.AreEqual(36, ALayout.Members[5].BodyLastLine);
    end);
end;

procedure TClassLayoutTests.KnowsUses;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    var
      Used: TArray<Integer>;
    begin
      // GetName benutzt FA; Load(Integer) benutzt FB, aber nicht Other.FA.
      Used := ALayout.UsedBy(2);
      Assert.AreEqual(1, Integer(Length(Used)));
      Assert.AreEqual(0, Used[0]);
      Used := ALayout.UsedBy(3);
      Assert.AreEqual(1, Integer(Length(Used)));
      Assert.AreEqual(1, Used[0]);
      // Load(string) ruft Self.Load: Die andere Überladung zählt, sich selbst nicht.
      Used := ALayout.UsedBy(4);
      Assert.AreEqual(1, Integer(Length(Used)));
      Assert.AreEqual(3, Used[0]);
      // Property Name benutzt GetName und FB.
      Assert.AreEqual(2, Integer(Length(ALayout.UsedBy(6))));
      // FA wird von GetName benutzt.
      Used := ALayout.UsersOf(0);
      Assert.AreEqual(1, Integer(Length(Used)));
      Assert.AreEqual(2, Used[0]);
    end);
end;

procedure TClassLayoutTests.DeletesMemberWithBody;
var
  mResult_: string;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, TClassEdits.DeleteMember(ALayout, 5, True));
    end);
  Assert.IsFalse(mResult_.Contains('Make'), mResult_);
  Assert.IsTrue(Parses(mResult_), mResult_);
  Assert.IsFalse(mResult_.Contains(#10#10#10), 'keine doppelten Leerzeilen: ' + mResult_);
end;

procedure TClassLayoutTests.DeletesNameOfFieldGroup;
var
  mResult_: string;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, TClassEdits.DeleteMembers(ALayout, [0], False));
    end);
  Assert.IsTrue(mResult_.Contains('    FB: Integer;'#10), mResult_);
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, TClassEdits.DeleteMembers(ALayout, [0, 1], False));
    end);
  Assert.IsFalse(mResult_.Contains('FA, FB'), mResult_);
  Assert.IsTrue(mResult_.Contains('  private'#10'    function GetName'), mResult_);
end;

procedure TClassLayoutTests.InsertsFieldsBeforeMethods;
var
  mResult_: string;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, [TClassEdits.InsertMembers(ALayout, TClassVisibility.Private_,
        True, ['FC: string;'])]);
    end);
  Assert.IsTrue(mResult_.Contains('    FA, FB: Integer;'#10'    FC: string;'#10'    function GetName'), mResult_);
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, [TClassEdits.InsertMembers(ALayout, TClassVisibility.Public_,
        False, ['procedure Save;'])]);
    end);
  Assert.IsTrue(mResult_.Contains('write FB;'#10'    procedure Save;'#10'  end;'), mResult_);
  Assert.IsTrue(Parses(mResult_), mResult_);
end;

procedure TClassLayoutTests.InsertsNewSection;
var
  mResult_: string;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, [TClassEdits.InsertMembers(ALayout,
        TClassVisibility.StrictProtected, False, ['procedure DoIt; virtual;'])]);
    end);
  // Zwischen private und public, nach Sichtbarkeit geordnet.
  Assert.IsTrue(mResult_.Contains('function GetName: string;'#10'  strict protected'#10'    procedure DoIt; virtual;'#10 +
    '  public'), mResult_);
  Assert.IsTrue(Parses(mResult_), mResult_);
end;

procedure TClassLayoutTests.SetsAncestors;
var
  mResult_: string;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, [TClassEdits.SetAncestors(ALayout, ['TNeu', 'IFoo', 'IBar'])]);
    end);
  Assert.IsTrue(mResult_.Contains('TKunde = class abstract(TNeu, IFoo, IBar)'), mResult_);
  WithLayout(StringReplace(cSource, 'class abstract(TBasis, IFoo)', 'class', []),
    procedure(ALayout: TClassLayout)
    begin
      mResult_ := TTextChanges.Apply(ALayout.Text, [TClassEdits.SetAncestors(ALayout, ['TInterfacedObject', 'IKunde'])]);
    end);
  Assert.IsTrue(mResult_.Contains('TKunde = class(TInterfacedObject, IKunde)'), mResult_);
end;

procedure TClassLayoutTests.CopiesBodyWithOtherClass;
var
  mBody: string;
begin
  WithLayout(cSource,
    procedure(ALayout: TClassLayout)
    begin
      mBody := TClassEdits.BodyText(ALayout, 5, 'TBasis');
    end);
  Assert.AreEqual('class function TBasis.Make: TKunde;'#10'begin'#10'  Result := TKunde.Create;'#10'end;', mBody);
end;

procedure TClassLayoutTests.DiffGivesLineEdits;
var
  mOld, mNew_: string;
  mEdits: TArray<TTextEdit>;
begin
  mOld := 'a'#10'b'#10'c'#10'd'#10'e';
  mNew_ := 'a'#10'B'#10'c'#10'd'#10'e'#10'f';
  mEdits := TTextChanges.Diff(mOld, mNew_);
  Assert.AreEqual(2, Integer(Length(mEdits)));
  Assert.AreEqual(mNew_, TTextChanges.Apply(mOld, mEdits));
  Assert.AreEqual(1, mEdits[0].Range.StartPos.Line);
  mNew_ := 'x'#10'a'#10'c'#10'e';
  Assert.AreEqual(mNew_, TTextChanges.Apply(mOld, TTextChanges.Diff(mOld, mNew_)));
  mNew_ := 'a'#10'b';
  Assert.AreEqual(mNew_, TTextChanges.Apply(mOld, TTextChanges.Diff(mOld, mNew_)));
  mOld := 'a'#13#10'b'#13#10;
  mNew_ := 'a'#13#10'x'#13#10'b'#13#10;
  Assert.AreEqual(mNew_, TTextChanges.Apply(mOld, TTextChanges.Diff(mOld, mNew_)));
  Assert.AreEqual(0, Integer(Length(TTextChanges.Diff(mOld, mOld))));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassLayoutTests);

end.
