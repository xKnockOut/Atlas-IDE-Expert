unit Atlas.Common.Editing.AssignFields.Tests;

// Tests für „Alle Felder zuweisen“ (#491) ohne Namensauflösung: beschreibbare Mitglieder, Vorgaben, schon
// zugewiesene Felder und der Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAssignFieldsTests = class
  public
    [Test]
    procedure WritableMembers;
    [Test]
    procedure MergesRedeclaredProperties;
    [Test]
    procedure DefaultValues;
    [Test]
    procedure SkipsAssignedFields;
    [Test]
    procedure BuildsText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.AssignFields;

function Member(const AName: string; AKind: TIndexSymbolKind; const ASignature, ATypeName: string;
  AVisibility: TIndexVisibility): TAssignMember;
begin
  Result := Default(TAssignMember);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Signature := ASignature;
  Result.TypeName := ATypeName;
  Result.Visibility := AVisibility;
end;

function Field(const AName, AValue: string): TAssignField;
begin
  Result := Default(TAssignField);
  Result.Name := AName;
  Result.Value := AValue;
end;

procedure TAssignFieldsTests.WritableMembers;
var
  Indexed: TAssignMember;
begin
  Assert.IsTrue(TAssignFields.Writable(Member('Count', TIndexSymbolKind.Field, 'Count: Integer', 'Integer',
    TIndexVisibility.Public)));
  Assert.IsFalse(TAssignFields.Writable(Member('FCount', TIndexSymbolKind.Field, 'FCount: Integer', 'Integer',
    TIndexVisibility.Private)), 'privat');
  Assert.IsTrue(TAssignFields.Writable(Member('Name', TIndexSymbolKind.Property_,
    'property Name: string read FName write SetName', 'string', TIndexVisibility.Published)));
  Assert.IsFalse(TAssignFields.Writable(Member('Size', TIndexSymbolKind.Property_,
    'property Size: Integer read GetSize', 'Integer', TIndexVisibility.Public)), 'nur lesbar');
  // "Write" im Namen oder Typ ist kein Schreibzugriff.
  Assert.IsFalse(TAssignFields.Writable(Member('Write', TIndexSymbolKind.Property_,
    'property Write: TWriteMode read FWrite', 'TWriteMode', TIndexVisibility.Public)));
  Indexed := Member('Items', TIndexSymbolKind.Property_, 'property Items[I: Integer]: string read Get write Put',
    'string', TIndexVisibility.Public);
  Indexed.MaxArgs := 1;
  Assert.IsFalse(TAssignFields.Writable(Indexed), 'indiziert');
  Assert.IsFalse(TAssignFields.Writable(Member('Run', TIndexSymbolKind.Method, 'procedure Run', '',
    TIndexVisibility.Public)), 'Methode');
end;

procedure TAssignFieldsTests.MergesRedeclaredProperties;
var
  Merged: TArray<TAssignMember>;
begin
  Merged := TAssignFields.Merge([
    Member('Caption', TIndexSymbolKind.Property_, 'property Caption: string read FCaption write FCaption',
      'string', TIndexVisibility.Protected),
    Member('Tag', TIndexSymbolKind.Field, 'Tag: Integer', 'Integer', TIndexVisibility.Public),
    Member('Caption', TIndexSymbolKind.Property_, 'property Caption', '', TIndexVisibility.Published)]);
  Assert.AreEqual(2, Integer(Length(Merged)));
  Assert.AreEqual('Caption', Merged[0].Name, 'an der Stelle der geerbten');
  Assert.IsTrue(Merged[0].Visibility = TIndexVisibility.Published);
  Assert.AreEqual('string', Merged[0].TypeName);
  Assert.IsTrue(TAssignFields.Writable(Merged[0]));
  Merged := nil;
end;

procedure TAssignFieldsTests.DefaultValues;
var
  Kind: TAssignValueKind;
begin
  Assert.IsTrue(TAssignFields.KindOfText('Integer', Kind) and (Kind = TAssignValueKind.Number));
  Assert.IsTrue(TAssignFields.KindOfText('System.Double', Kind) and (Kind = TAssignValueKind.Number));
  Assert.IsTrue(TAssignFields.KindOfText('TDateTime', Kind) and (Kind = TAssignValueKind.Number));
  Assert.IsTrue(TAssignFields.KindOfText('string', Kind) and (Kind = TAssignValueKind.Text));
  Assert.IsTrue(TAssignFields.KindOfText('string[20]', Kind) and (Kind = TAssignValueKind.Text));
  Assert.IsTrue(TAssignFields.KindOfText('Char', Kind) and (Kind = TAssignValueKind.Character));
  Assert.IsTrue(TAssignFields.KindOfText('Boolean', Kind) and (Kind = TAssignValueKind.Boolean_));
  Assert.IsTrue(TAssignFields.KindOfText('TArray<Integer>', Kind) and (Kind = TAssignValueKind.Reference));
  Assert.IsTrue(TAssignFields.KindOfText('array of Byte', Kind) and (Kind = TAssignValueKind.Reference));
  Assert.IsTrue(TAssignFields.KindOfText('^TNode', Kind) and (Kind = TAssignValueKind.Reference));
  Assert.IsTrue(TAssignFields.KindOfText('reference to procedure', Kind) and (Kind = TAssignValueKind.Reference));
  Assert.IsTrue(TAssignFields.KindOfText('set of TKind', Kind) and (Kind = TAssignValueKind.SetOf));
  Assert.IsFalse(TAssignFields.KindOfText('TOptions', Kind), 'braucht die Namensauflösung');
  Assert.IsFalse(TAssignFields.KindOfText('Settings', Kind), 'nicht als set erkannt');
  Assert.AreEqual('0', TAssignFields.DefaultValue(TAssignValueKind.Number, 'Integer', ''));
  Assert.AreEqual('''''', TAssignFields.DefaultValue(TAssignValueKind.Text, 'string', ''));
  Assert.AreEqual('#0', TAssignFields.DefaultValue(TAssignValueKind.Character, 'Char', ''));
  Assert.AreEqual('False', TAssignFields.DefaultValue(TAssignValueKind.Boolean_, 'Boolean', ''));
  Assert.AreEqual('nil', TAssignFields.DefaultValue(TAssignValueKind.Reference, 'TObject', ''));
  Assert.AreEqual('[]', TAssignFields.DefaultValue(TAssignValueKind.SetOf, 'TKinds', ''));
  Assert.AreEqual('kA', TAssignFields.DefaultValue(TAssignValueKind.Enum, 'TKind', 'kA'));
  Assert.AreEqual('Default(TPoint)', TAssignFields.DefaultValue(TAssignValueKind.Other, 'TPoint', ''));
end;

procedure TAssignFieldsTests.SkipsAssignedFields;
var
  Lines: TArray<string>;
  Fields: TArray<TAssignField>;
begin
  Lines := ['  Opts.', '  Opts.Header := ''x'';', '', '  opts . Count:=1;', '  Foo;', '  Opts.Kind := kA;'];
  Assert.AreEqual('Header|Count', string.Join('|', TAssignFields.AssignedAfter(Lines, 0, 'Opts')));
  Assert.AreEqual('', string.Join('|', TAssignFields.AssignedAfter(Lines, 4, 'Other')));
  Assert.AreEqual('X', string.Join('|', TAssignFields.AssignedAfter(['A.B.', 'A.B.X := 1;'], 0, 'A.B')));
  Fields := TAssignFields.Without([Field('Header', ''''''), Field('Count', '0'), Field('Kind', 'kA')],
    ['count', 'Header']);
  Assert.AreEqual(1, Integer(Length(Fields)));
  Assert.AreEqual('Kind', Fields[0].Name);
  Lines := nil;
  Fields := nil;
end;

procedure TAssignFieldsTests.BuildsText;
var
  Fields: TArray<TAssignField>;
begin
  Fields := [Field('Header', ''''''), Field('Count', '0')];
  Assert.AreEqual('Opts.Header := '''';', TAssignFields.Line('Opts', Fields[0]));
  Assert.AreEqual('Opts.Header := ${1:''''};'#10'Opts.Count := ${2:0};', TAssignFields.Snippet('Opts', Fields));
  Assert.AreEqual('Opts.Header := '''';'#13#10'    Opts.Count := 0;',
    TAssignFields.Plain('Opts', '    ', #13#10, Fields));
  // Zeichen der Snippet-Syntax im Wert.
  Assert.AreEqual('A.B := ${1:Default(T\}\$)};', TAssignFields.Snippet('A', [Field('B', 'Default(T}$)')]));
  Assert.AreEqual('Alle Felder zuweisen (3)', TAssignFields.Title(3));
  Fields := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAssignFieldsTests);

end.
