unit Atlas.Core.Generate.FileTemplates;

// Dateivorlagen für „Neu mit Atlas“ (#759), ohne VCL und Open Tools API: Die
// Knöpfe Unit, Formular und Testklasse unter der Einrichtungskarte der
// Willkommensseite öffnen das Erzeugen-Menü (#719) nur mit den Dateivorlagen
// ihrer Art; die gewählte Vorlage wird als neue, noch unbenannte Datei im
// aktuellen Projekt angelegt (IDE-Schicht, IOTAModuleCreator).
//
// Dateivorlagen sind Code-Vorlagen (#51) mit "file: unit|form|test" im Kopf.
// Mitgeliefert: leere Unit, Unit mit Klasse, VCL-Formular, DUnitX-Testklasse;
// eigene Vorlagen im Ordner der Code-Vorlagen ersetzen mitgelieferte mit
// gleichem Kürzel oder kommen dazu. Variablen im Text:
//   %Unit%      Name der Unit, wie ihn die IDE vergibt (z. B. Unit2)
//   %Name%      derselbe ohne Namespace (für Klassennamen)
//   %Form%      Name des Formulars (z. B. Form2); bei Units wie %Name%
//   %Ancestor%  Basisklasse des Formulars ohne T (Vorgabe Form)
// Platzhalter (${1:…}) werden zu ihrem Vorgabetext, "$$" zu "$".

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Generate.Menu;

type
{$SCOPEDENUMS ON}
  /// <summary>Knöpfe „Neu mit Atlas“ in ihrer Reihenfolge.</summary>
  TAtlasNewFileKind = (UnitFile, FormFile, TestFile);
{$SCOPEDENUMS OFF}

  TAtlasFileTemplates = class
  public const
    /// <summary>Basisklasse eines Formulars ohne T, wenn die IDE keine nennt.</summary>
    DefaultAncestor = 'Form';
  public
    /// <summary>"unit", "form" bzw. "test" wie im Kopf "file:".</summary>
    class function KindWord(AKind: TAtlasNewFileKind): string; static;
    /// <summary>Mitgelieferte Dateivorlagen (Herkunft BuiltIn).</summary>
    class function BuiltIn: TAtlasSnippetList; static;
    /// <summary>Mitgelieferte und eigene Dateivorlagen (eigene ersetzen gleiche Kürzel) der Art AKind, in der
    /// Reihenfolge: mitgelieferte, dann eigene.</summary>
    class function OfKind(const AUser: TAtlasSnippetList; AKind: TAtlasNewFileKind): TAtlasSnippetList; static;
    /// <summary>Einträge für das Erzeugen-Menü (Gruppe Vorlagen); Source = Index in ATemplates.</summary>
    class function Entries(const ATemplates: TAtlasSnippetList): TArray<TAtlasGenerateEntry>; static;
    /// <summary>Text der neuen Datei: Variablen eingesetzt, Platzhalter aufgelöst, Zeilen mit ALineBreak, am Ende
    /// ein Zeilenende.</summary>
    class function Render(const ABody, AUnit, AForm, AAncestor, ALineBreak: string): string; static;
    /// <summary>Unit-Name ohne Namespace ("App.Kunden" → "Kunden").</summary>
    class function ShortName(const AUnit: string): string; static;
  end;

implementation

const
  EmptyUnitBody =
    'unit %Unit%;' + #10 +
    #10 +
    'interface' + #10 +
    #10 +
    'implementation' + #10 +
    #10 +
    'end.';
  ClassUnitBody =
    'unit %Unit%;' + #10 +
    #10 +
    'interface' + #10 +
    #10 +
    'type' + #10 +
    '  T%Name% = class' + #10 +
    '  private' + #10 +
    '  public' + #10 +
    '    constructor Create;' + #10 +
    '    destructor Destroy; override;' + #10 +
    '  end;' + #10 +
    #10 +
    'implementation' + #10 +
    #10 +
    '{ T%Name% }' + #10 +
    #10 +
    'constructor T%Name%.Create;' + #10 +
    'begin' + #10 +
    '  inherited Create;' + #10 +
    'end;' + #10 +
    #10 +
    'destructor T%Name%.Destroy;' + #10 +
    'begin' + #10 +
    '  inherited;' + #10 +
    'end;' + #10 +
    #10 +
    'end.';
  FormBody =
    'unit %Unit%;' + #10 +
    #10 +
    'interface' + #10 +
    #10 +
    'uses' + #10 +
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,' + #10 +
    '  Vcl.Controls, Vcl.Forms, Vcl.Dialogs;' + #10 +
    #10 +
    'type' + #10 +
    '  T%Form% = class(T%Ancestor%)' + #10 +
    '  private' + #10 +
    '  public' + #10 +
    '  end;' + #10 +
    #10 +
    'var' + #10 +
    '  %Form%: T%Form%;' + #10 +
    #10 +
    'implementation' + #10 +
    #10 +
    '{$R *.dfm}' + #10 +
    #10 +
    'end.';
  TestBody =
    'unit %Unit%;' + #10 +
    #10 +
    'interface' + #10 +
    #10 +
    'uses' + #10 +
    '  DUnitX.TestFramework;' + #10 +
    #10 +
    'type' + #10 +
    '  [TestFixture]' + #10 +
    '  T%Name%Tests = class' + #10 +
    '  public' + #10 +
    '    [Setup]' + #10 +
    '    procedure Setup;' + #10 +
    '    [TearDown]' + #10 +
    '    procedure TearDown;' + #10 +
    '    [Test]' + #10 +
    '    procedure FirstTest;' + #10 +
    '  end;' + #10 +
    #10 +
    'implementation' + #10 +
    #10 +
    'procedure T%Name%Tests.Setup;' + #10 +
    'begin' + #10 +
    'end;' + #10 +
    #10 +
    'procedure T%Name%Tests.TearDown;' + #10 +
    'begin' + #10 +
    'end;' + #10 +
    #10 +
    'procedure T%Name%Tests.FirstTest;' + #10 +
    'begin' + #10 +
    '  Assert.Pass;' + #10 +
    'end;' + #10 +
    #10 +
    'initialization' + #10 +
    '  TDUnitX.RegisterTestFixture(T%Name%Tests);' + #10 +
    #10 +
    'end.';

function Template(const APrefix, AName, ADescription, AKind, ABody: string): TAtlasSnippet;
begin
  Result := Default(TAtlasSnippet);
  Result.Prefix := APrefix;
  Result.Name := AName;
  Result.Description := ADescription;
  Result.FileKind := AKind;
  Result.Body := ABody;
  Result.Origin := TAtlasSnippetOrigin.BuiltIn;
end;

{ TAtlasFileTemplates }

class function TAtlasFileTemplates.KindWord(AKind: TAtlasNewFileKind): string;
begin
  case AKind of
    TAtlasNewFileKind.FormFile:
      Result := 'form';
    TAtlasNewFileKind.TestFile:
      Result := 'test';
  else
    Result := 'unit';
  end;
end;

class function TAtlasFileTemplates.BuiltIn: TAtlasSnippetList;
begin
  // Namen und Beschreibungen deutsch wie die übrigen mitgelieferten Code-Vorlagen (#51).
  Result := [
    Template('newunit', 'Leere Unit', 'interface und implementation, sonst nichts', 'unit', EmptyUnitBody),
    Template('newclass', 'Unit mit Klasse', 'Klasse mit Konstruktor und Destruktor', 'unit', ClassUnitBody),
    Template('newform', 'VCL-Formular', 'Formular mit .dfm', 'form', FormBody),
    Template('newtest', 'DUnitX-Testklasse', 'Testklasse mit Setup, TearDown und RegisterTestFixture', 'test',
      TestBody)];
end;

class function TAtlasFileTemplates.OfKind(const AUser: TAtlasSnippetList;
  AKind: TAtlasNewFileKind): TAtlasSnippetList;
var
  Item: TAtlasSnippet;
  Word: string;
begin
  Result := nil;
  Word := KindWord(AKind);
  for Item in TAtlasSnippets.Merge(BuiltIn, TAtlasSnippets.FileTemplates(AUser)) do
    if SameText(Item.FileKind, Word) then
      Result := Result + [Item];
end;

class function TAtlasFileTemplates.Entries(const ATemplates: TAtlasSnippetList): TArray<TAtlasGenerateEntry>;
var
  Index: Integer;
  Entry: TAtlasGenerateEntry;
begin
  Result := nil;
  for Index := 0 to High(ATemplates) do
  begin
    Entry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates,
      ATemplates[Index].Prefix, ATemplates[Index].Name);
    if Entry.Caption = '' then
      Entry.Caption := ATemplates[Index].Prefix;
    Entry.Detail := ATemplates[Index].Description;
    Entry.Source := Index;
    Result := Result + [Entry];
  end;
end;

class function TAtlasFileTemplates.ShortName(const AUnit: string): string;
var
  Index: Integer;
begin
  Result := Trim(AUnit);
  for Index := Length(Result) downto 1 do
    if Result[Index] = '.' then
      Exit(Copy(Result, Index + 1, MaxInt));
end;

class function TAtlasFileTemplates.Render(const ABody, AUnit, AForm, AAncestor, ALineBreak: string): string;
var
  Form, Ancestor: string;
begin
  Form := Trim(AForm);
  if Form = '' then
    Form := ShortName(AUnit);
  Ancestor := Trim(AAncestor);
  if Ancestor = '' then
    Ancestor := DefaultAncestor;
  Result := ABody;
  Result := StringReplace(Result, '%Unit%', Trim(AUnit), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%Name%', ShortName(AUnit), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%Form%', Form, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%Ancestor%', Ancestor, [rfReplaceAll, rfIgnoreCase]);
  Result := TAtlasSnippets.PlainText(Result);
  while (Result <> '') and CharInSet(Result[Length(Result)], [#10, ' ']) do
    Delete(Result, Length(Result), 1);
  Result := StringReplace(Result + #10, #10, ALineBreak, [rfReplaceAll]);
end;

end.
