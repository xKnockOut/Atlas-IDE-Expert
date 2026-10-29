unit Atlas.Core.Signature.Contract;

// Daten des Parameter-Hints (#436): Signaturen eines Aufrufs mit der Lage der
// Parameter im Text, aktiver Signatur und aktivem Parameter, wie sie der
// Server über textDocument/signatureHelp liefert (#32).
// Platzhalter (#451): Bei Format und anderen Formatroutinen ordnet der Server
// unter "format" jedem Platzhalter sein Argument in der Liste [...] zu, mit der
// Lage im Dokument und einem erkannten Problem.

interface

uses
  System.SysUtils;

type
  TAtlasSignatureParameter = record
    /// <summary>Lage im Label der Signatur, 0-basiert, Stop exklusiv; -1 wenn unbekannt.</summary>
    Start: Integer;
    Stop: Integer;
    /// <summary>Doku des Parameters aus XMLDoc; '' ohne.</summary>
    Documentation: string;
    /// <summary>Text des Parameters im Label.</summary>
    function Text(const ALabel: string): string;
  end;

  TAtlasSignature = record
    /// <summary>Ganze Signatur, z. B. "function Format(const Format: string; const Args: array of const): string".</summary>
    Label_: string;
    Documentation: string;
    Parameters: TArray<TAtlasSignatureParameter>;
    /// <summary>Ein bisheriges Argument passt nach seinem Typ nicht (#498, data.fits vom Server); False, wenn alle
    /// passen oder der Server nichts sagt.</summary>
    TypeMismatch: Boolean;
    /// <summary>Erstes unverträgliches Argument (0-basiert), nur mit TypeMismatch.</summary>
    MismatchArgument: Integer;
  end;

  /// <summary>Lage im Dokument: Zeile und Zeichen ab 0, Ende exklusiv.</summary>
  TAtlasFormatRange = record
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    function IsEmpty: Boolean;
  end;

  TAtlasFormatPlaceholder = record
    Text: string;
    /// <summary>Typbuchstabe klein (d u e f g n m p s x); #0 bei ungültigen Platzhaltern.</summary>
    TypeChar: Char;
    Valid: Boolean;
    /// <summary>Argumente ab 0, -1 = keins.</summary>
    Argument: Integer;
    WidthArgument: Integer;
    PrecisionArgument: Integer;
    /// <summary>Nur wenn der Formatstring als Literal im Aufruf steht.</summary>
    HasRange: Boolean;
    Range: TAtlasFormatRange;
  end;

  {$SCOPEDENUMS ON}
  TAtlasFormatProblem = (None, Invalid, TooManyArguments, TypeConflict);
  {$SCOPEDENUMS OFF}

  TAtlasSignatureFormat = record
    Found: Boolean;
    FormatParameter: Integer;
    ListParameter: Integer;
    /// <summary>Höchstes verwendetes Argument + 1; -1 bei Index "*".</summary>
    ArgumentCount: Integer;
    /// <summary>Eintrag der Liste am Cursor, -1 außerhalb.</summary>
    ActiveArgument: Integer;
    Placeholders: TArray<TAtlasFormatPlaceholder>;
    /// <summary>Einträge der Liste, auch leere.</summary>
    Arguments: TArray<TAtlasFormatRange>;
    Problem: TAtlasFormatProblem;
    ProblemPlaceholder: Integer;
    ProblemArgument: Integer;
    /// <summary>Art des Literals beim Typkonflikt: string, char, integer, float, boolean.</summary>
    ProblemKind: string;
  end;

  TAtlasSignatureHelp = record
    Signatures: TArray<TAtlasSignature>;
    /// <summary>Vom Server gewählte Signatur bzw. -1.</summary>
    ActiveSignature: Integer;
    /// <summary>Vom Server ermittelter Parameter bzw. -1.</summary>
    ActiveParameter: Integer;
    /// <summary>Platzhalter einer Formatroutine (#451).</summary>
    Format: TAtlasSignatureFormat;
    function IsEmpty: Boolean;
  end;

  TAtlasSignatureCallback = reference to procedure(const AHelp: TAtlasSignatureHelp);

  /// <summary>Quelle des Parameter-Hints; die Kompositionswurzel setzt den Server-Anbieter ein (A-09).</summary>
  IAtlasSignatureSource = interface
    ['{9C248983-E271-4AC1-9F44-417B651EC5B4}']
    /// <summary>Fragt im Hintergrund; ACallback im Hauptthread. False, wenn nichts gestartet wurde.</summary>
    function Query(const AFileName, AText: string; ALine, ACharacter: Integer;
      const ACallback: TAtlasSignatureCallback): Boolean;
    procedure Cancel;
    /// <summary>Bricht laufende Anfragen ab und wartet auf sie.</summary>
    procedure Shutdown;
  end;

implementation

{ TAtlasSignatureParameter }

function TAtlasSignatureParameter.Text(const ALabel: string): string;
begin
  if (Start >= 0) and (Stop > Start) then
    Result := Copy(ALabel, Start + 1, Stop - Start)
  else
    Result := '';
end;

{ TAtlasFormatRange }

function TAtlasFormatRange.IsEmpty: Boolean;
begin
  Result := (StartLine = EndLine) and (StartCharacter >= EndCharacter);
end;

{ TAtlasSignatureHelp }

function TAtlasSignatureHelp.IsEmpty: Boolean;
begin
  Result := Length(Signatures) = 0;
end;

end.
