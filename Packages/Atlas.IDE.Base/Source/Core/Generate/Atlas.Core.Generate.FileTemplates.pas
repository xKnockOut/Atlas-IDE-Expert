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
    cDefaultAncestor = 'Form';
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


uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TFileTemplatesText = (EmptyUnit, InterfaceAndImplementationNothingElse, UnitWithClass,
    ClassWithConstructorAndDestructor, VCLForm, FormWithDfm, DUnitXTestClass, TestClassWithSetupTearDown);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TFileTemplatesText] of string = (
    ('Leere Unit',
     'interface und implementation, sonst nichts',
     'Unit mit Klasse',
     'Klasse mit Konstruktor und Destruktor',
     'VCL-Formular',
     'Formular mit .dfm',
     'DUnitX-Testklasse',
     'Testklasse mit Setup, TearDown und RegisterTestFixture'),
    ('Empty unit',
     'interface and implementation, nothing else',
     'Unit with class',
     'Class with constructor and destructor',
     'VCL form',
     'Form with .dfm',
     'DUnitX test class',
     'Test class with Setup, TearDown and RegisterTestFixture'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TFileTemplatesText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;
const
  cEmptyUnitBody =
    'unit %Unit%;' + #10 +
    #10 +
    'interface' + #10 +
    #10 +
    'implementation' + #10 +
    #10 +
    'end.';
  cClassUnitBody =
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
  cFormBody =
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
  cTestBody =
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
  // Namen und Beschreibungen in der Sprache der Oberfläche wie die übrigen mitgelieferten Code-Vorlagen (#51).
  Result := [
    Template('newunit', UiText(TFileTemplatesText.EmptyUnit),
      UiText(TFileTemplatesText.InterfaceAndImplementationNothingElse), 'unit', cEmptyUnitBody),
    Template('newclass', UiText(TFileTemplatesText.UnitWithClass),
      UiText(TFileTemplatesText.ClassWithConstructorAndDestructor), 'unit', cClassUnitBody),
    Template('newform', UiText(TFileTemplatesText.VCLForm), UiText(TFileTemplatesText.FormWithDfm), 'form', cFormBody),
    Template('newtest', UiText(TFileTemplatesText.DUnitXTestClass), UiText(TFileTemplatesText.TestClassWithSetupTearDown), 'test',
      cTestBody)];
end;

class function TAtlasFileTemplates.OfKind(const AUser: TAtlasSnippetList;
  AKind: TAtlasNewFileKind): TAtlasSnippetList;
var
  mItem: TAtlasSnippet;
  mWord: string;
begin
  Result := nil;
  mWord := KindWord(AKind);
  for mItem in TAtlasSnippets.Merge(BuiltIn, TAtlasSnippets.FileTemplates(AUser)) do
  begin
    if SameText(mItem.FileKind, mWord) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasFileTemplates.Entries(const ATemplates: TAtlasSnippetList): TArray<TAtlasGenerateEntry>;
var
  mIndex: Integer;
  mEntry: TAtlasGenerateEntry;
begin
  Result := nil;
  for mIndex := 0 to High(ATemplates) do
  begin
    mEntry := TAtlasGenerateEntry.Create(TAtlasGenerateKind.Snippet, TAtlasGenerateGroup.Templates,
      ATemplates[mIndex].Prefix, ATemplates[mIndex].Name);
    if mEntry.Caption = '' then
    begin
      mEntry.Caption := ATemplates[mIndex].Prefix;
    end;
    mEntry.Detail := ATemplates[mIndex].Description;
    mEntry.Source := mIndex;
    Result := Result + [mEntry];
  end;
end;

class function TAtlasFileTemplates.ShortName(const AUnit: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(AUnit);
  for mIndex := Length(Result) downto 1 do
  begin
    if Result[mIndex] = '.' then
    begin
      Exit(Copy(Result, mIndex + 1, MaxInt));
    end;
  end;
end;

class function TAtlasFileTemplates.Render(const ABody, AUnit, AForm, AAncestor, ALineBreak: string): string;
var
  mForm, mAncestor: string;
begin
  mForm := Trim(AForm);
  if mForm = '' then
  begin
    mForm := ShortName(AUnit);
  end;
  mAncestor := Trim(AAncestor);
  if mAncestor = '' then
  begin
    mAncestor := cDefaultAncestor;
  end;
  Result := ABody;
  Result := StringReplace(Result, '%Unit%', Trim(AUnit), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%Name%', ShortName(AUnit), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%Form%', mForm, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '%Ancestor%', mAncestor, [rfReplaceAll, rfIgnoreCase]);
  Result := TAtlasSnippets.PlainText(Result);
  while (Result <> '') and CharInSet(Result[Length(Result)], [#10, ' ']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
  Result := StringReplace(Result + #10, #10, ALineBreak, [rfReplaceAll]);
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Generate.FileTemplates', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
