unit Atlas.Core.Assistants.Contract.Link;

// Assistenten-Kopplung (#2377), Vertrag zwischen dem Protokoll (Atlas.Core.Assistants.LinkProtocol) und der IDE:
// was die IDE dem verbundenen Assistenten liefert und für ihn tut (IAtlasLinkIde), der Ausgang einer Verbindung
// (IAtlasLinkPeer) und die Records dazwischen. Zeilen und Zeichen sind 0-basiert wie im LSP.

interface

uses
  System.SysUtils;

type
  TAtlasLinkPosition = record
    Line: Integer;
    Character: Integer;
    class function At(ALine, ACharacter: Integer): TAtlasLinkPosition; static;
  end;

  /// <summary>Auswahl im Editor; Known = False ohne Editor.</summary>
  TAtlasLinkSelection = record
    Known: Boolean;
    FileName: string;
    Text: string;
    Start: TAtlasLinkPosition;
    Stop: TAtlasLinkPosition;
    function IsEmpty: Boolean;
    /// <summary>Schlüssel für die Entprellung: Datei und Bereich (der Text folgt dem Bereich).</summary>
    function Key: string;
  end;

  /// <summary>Ein offener Reiter.</summary>
  TAtlasLinkTab = record
    FileName: string;
    Active: Boolean;
    Dirty: Boolean;
  end;

  /// <summary>Ein Befund oder eine Compilermeldung; Severity ist 'Error', 'Warning', 'Information' oder 'Hint'.
  /// </summary>
  TAtlasLinkDiagnostic = record
    FileName: string;
    Message: string;
    Severity: string;
    Source: string;
    Code: string;
    Start: TAtlasLinkPosition;
    Stop: TAtlasLinkPosition;
  end;

  /// <summary>Parameter von openFile.</summary>
  TAtlasLinkOpenRequest = record
    FileName: string;
    StartText: string;
    EndText: string;
    SelectToEndOfLine: Boolean;
    MakeFrontmost: Boolean;
  end;

  /// <summary>Ergebnis von openFile.</summary>
  TAtlasLinkOpenResult = record
    Opened: Boolean;
    LineCount: Integer;
  end;

  /// <summary>Zustand einer Datei für checkDocumentDirty.</summary>
  TAtlasLinkDocument = record
    Open: Boolean;
    Dirty: Boolean;
  end;

  /// <summary>Parameter von openDiff.</summary>
  TAtlasLinkDiffRequest = record
    OldFileName: string;
    NewFileName: string;
    NewText: string;
    TabName: string;
  end;

  /// <summary>Entscheidung über einen Vorschlag: angenommen mit AText (so steht die Datei jetzt), sonst abgelehnt.
  /// </summary>
  TAtlasLinkDiffDone = reference to procedure(AAccepted: Boolean; const AText: string);

  /// <summary>Was die IDE dem Protokoll liefert und für es tut; alle Aufrufe im Hauptthread.</summary>
  IAtlasLinkIde = interface
    ['{6C2E9A41-8B3D-4F07-9E15-D4A7B0C38F62}']
    function WorkspaceFolders: TArray<string>;
    function OpenTabs: TArray<TAtlasLinkTab>;
    function CurrentSelection: TAtlasLinkSelection;
    function LatestSelection: TAtlasLinkSelection;
    function OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult;
    function Document(const AFileName: string): TAtlasLinkDocument;
    function SaveDocument(const AFileName: string): Boolean;
    /// <summary>Befunde und Compilermeldungen von AFileName; '' = aller offenen Dateien.</summary>
    function Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>;
    /// <summary>Vorschlag zeigen; ADone genau einmal, nach der Entscheidung (auch beim Schließen).</summary>
    procedure OpenDiff(const ARequest: TAtlasLinkDiffRequest; const ADone: TAtlasLinkDiffDone);
    function CloseTab(const ATabName: string): Boolean;
    function CloseAllDiffs: Integer;
    /// <summary>Pause für KI-Assistenten (#1906): Änderungen werden abgelehnt.</summary>
    function Paused: Boolean;
  end;

  /// <summary>Die Gegenstelle einer Verbindung; Send nach dem Trennen tut nichts.</summary>
  IAtlasLinkPeer = interface
    ['{1F8B6D27-3C59-4A0E-B7D4-92E05C1A6B38}']
    procedure Send(const AJson: string);
  end;

implementation

{ TAtlasLinkPosition }

class function TAtlasLinkPosition.At(ALine, ACharacter: Integer): TAtlasLinkPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

{ TAtlasLinkSelection }

function TAtlasLinkSelection.IsEmpty: Boolean;
begin
  Result := (Start.Line = Stop.Line) and (Start.Character = Stop.Character);
end;

function TAtlasLinkSelection.Key: string;
begin
  if not Known then
  begin
    Result := '';
    Exit;
  end;
  Result := Format('%s|%d:%d-%d:%d|%d', [FileName, Start.Line, Start.Character, Stop.Line, Stop.Character,
    Length(Text)]);
end;

end.
