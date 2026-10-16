unit Atlas.Core.Signature.Contract;

// Daten des Parameter-Hints (#436): Signaturen eines Aufrufs mit der Lage der
// Parameter im Text, aktiver Signatur und aktivem Parameter, wie sie der
// Server über textDocument/signatureHelp liefert (#32).

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
  end;

  TAtlasSignatureHelp = record
    Signatures: TArray<TAtlasSignature>;
    /// <summary>Vom Server gewählte Signatur bzw. -1.</summary>
    ActiveSignature: Integer;
    /// <summary>Vom Server ermittelter Parameter bzw. -1.</summary>
    ActiveParameter: Integer;
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

{ TAtlasSignatureHelp }

function TAtlasSignatureHelp.IsEmpty: Boolean;
begin
  Result := Length(Signatures) = 0;
end;

end.
