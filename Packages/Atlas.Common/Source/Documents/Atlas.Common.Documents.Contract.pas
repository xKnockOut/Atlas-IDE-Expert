unit Atlas.Common.Documents.Contract;

// Contract des Platform-Features Documents: im Editor geöffnete Dateien als
// unveränderliche Momentaufnahmen und der Speicher, der sie verwaltet.
//
// Positionen zählen wie im LSP in UTF-16-Codeeinheiten. Das entspricht den
// Zeichen eines Delphi-string, Zeile und Spalte beginnen bei 0.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  /// <summary>Position im Text: Zeile und Spalte, beide ab 0, Spalte in UTF-16-Codeeinheiten.</summary>
  TTextPosition = record
    Line: Integer;
    Character: Integer;
    constructor Create(ALine, ACharacter: Integer);
    class operator Equal(const A, B: TTextPosition): Boolean;
    class operator NotEqual(const A, B: TTextPosition): Boolean;
  end;

  /// <summary>Bereich von StartPos (einschließlich) bis EndPos (ausschließlich).</summary>
  TTextRange = record
    StartPos: TTextPosition;
    EndPos: TTextPosition;
    constructor Create(const AStartPos, AEndPos: TTextPosition); overload;
    constructor Create(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer); overload;
  end;

  /// <summary>Eine Änderung aus didChange: ersetzt einen Bereich oder den ganzen Text.</summary>
  TTextChange = record
    HasRange: Boolean;
    Range: TTextRange;
    Text: string;
    /// <summary>Ersetzt den ganzen Text.</summary>
    class function Full(const AText: string): TTextChange; static;
    /// <summary>Ersetzt ARange durch AText.</summary>
    class function Ranged(const ARange: TTextRange; const AText: string): TTextChange; static;
  end;

  /// <summary>
  /// Unveränderliche Momentaufnahme eines Dokuments. Threadsicher lesbar, auch
  /// in nebenläufigen Anfragen, während der Editor weiter ändert.
  /// </summary>
  ITextDocument = interface
    ['{8B3E2D71-5C4A-4F9E-A1B6-0D7C9E2F4A63}']
    function GetUri: string;
    function GetLanguageId: string;
    function GetVersion: Integer;
    function GetText: string;
    function GetLineCount: Integer;
    /// <summary>Text der Zeile ohne Zeilenumbruch; außerhalb des Dokuments leer.</summary>
    function LineText(ALine: Integer): string;
    /// <summary>
    /// Offset ab 0 in Text. Eine Spalte hinter dem Zeilenende zählt als
    /// Zeilenende, eine Zeile hinter dem Dokument als Dokumentende (LSP-Spezifikation).
    /// </summary>
    function OffsetAt(const APosition: TTextPosition): Integer;
    /// <summary>Position zu einem Offset ab 0; Werte außerhalb werden begrenzt.</summary>
    function PositionAt(AOffset: Integer): TTextPosition;
    /// <summary>Neue Momentaufnahme mit den Änderungen, nacheinander angewendet.</summary>
    function ApplyChanges(const AChanges: TArray<TTextChange>; AVersion: Integer): ITextDocument;
    /// <summary>
    /// Aus dieser Momentaufnahme abgeleitete Daten unter AKey, z. B. der Syntaxbaum (#262).
    /// Der erste Aufruf erzeugt sie mit AFactory, gleichzeitige Aufrufer warten auf dasselbe
    /// Ergebnis. Liefert AFactory nil, wird nichts abgelegt. Die Daten leben so lange wie die
    /// Momentaufnahme.
    /// </summary>
    function Derived(const AKey: string; const AFactory: TFunc<IInterface>): IInterface;
    property Uri: string read GetUri;
    property LanguageId: string read GetLanguageId;
    property Version: Integer read GetVersion;
    property Text: string read GetText;
    property LineCount: Integer read GetLineCount;
  end;

  TDocumentEventKind = (Opened, Changed, Saved, Closed);

  /// <summary>
  /// Wird nach jeder Änderung am Speicher im Thread der Nachrichtenschleife
  /// aufgerufen, z. B. um nur die betroffene Datei neu zu parsen.
  /// Bei Closed ist ADocument der letzte Stand.
  /// </summary>
  TDocumentListener = reference to procedure(AKind: TDocumentEventKind; const ADocument: ITextDocument);

  /// <summary>Fehler bei der Dokumentverwaltung, z. B. Änderung an einem nicht geöffneten Dokument.</summary>
  EDocumentError = class(Exception);

  /// <summary>Die geöffneten Dokumente, je URI. Threadsicher.</summary>
  IDocumentStore = interface
    ['{2C9F6A15-8E3D-4B72-9A04-F5E1B8C3D726}']
    /// <summary>Öffnet ein Dokument; ein bereits geöffnetes wird ersetzt.</summary>
    function Open(const AUri, ALanguageId: string; AVersion: Integer; const AText: string): ITextDocument;
    /// <summary>Wendet Änderungen an. EDocumentError, wenn das Dokument nicht geöffnet ist.</summary>
    function Change(const AUri: string; AVersion: Integer; const AChanges: TArray<TTextChange>): ITextDocument;
    /// <summary>Meldet das Speichern; unbekannte Dokumente werden ignoriert.</summary>
    procedure Save(const AUri: string);
    /// <summary>Schließt ein Dokument; unbekannte Dokumente werden ignoriert.</summary>
    procedure Close(const AUri: string);
    function TryGet(const AUri: string; out ADocument: ITextDocument): Boolean;
    /// <summary>Momentaufnahmen aller geöffneten Dokumente.</summary>
    function Documents: TArray<ITextDocument>;
    procedure Subscribe(const AListener: TDocumentListener);
  end;

implementation

{ TTextPosition }

constructor TTextPosition.Create(ALine, ACharacter: Integer);
begin
  Line := ALine;
  Character := ACharacter;
end;

class operator TTextPosition.Equal(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Character = B.Character);
end;

class operator TTextPosition.NotEqual(const A, B: TTextPosition): Boolean;
begin
  Result := not (A = B);
end;

{ TTextRange }

constructor TTextRange.Create(const AStartPos, AEndPos: TTextPosition);
begin
  StartPos := AStartPos;
  EndPos := AEndPos;
end;

constructor TTextRange.Create(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer);
begin
  StartPos := TTextPosition.Create(AStartLine, AStartCharacter);
  EndPos := TTextPosition.Create(AEndLine, AEndCharacter);
end;

{ TTextChange }

class function TTextChange.Full(const AText: string): TTextChange;
begin
  Result := Default(TTextChange);
  Result.Text := AText;
end;

class function TTextChange.Ranged(const ARange: TTextRange; const AText: string): TTextChange;
begin
  Result := Default(TTextChange);
  Result.HasRange := True;
  Result.Range := ARange;
  Result.Text := AText;
end;

end.
