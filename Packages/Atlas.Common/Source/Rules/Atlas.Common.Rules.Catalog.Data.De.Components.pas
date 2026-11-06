unit Atlas.Common.Rules.Catalog.Data.De.Components;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeComponents: array[0..39] of string = (
    '{',
    '      "id": "component-create-without-override",',
    '      "name": "Komponentenkonstruktor ohne override",',
    '      "description": "Ein TComponent-Nachfahre deklariert constructor Create(AOwner: TComponent) ohne override. Beim Laden aus der Formulardatei wird der virtuelle Konstruktor benutzt und dieser überg' +
    'angen."',
    '    },',
    '{',
    '      "id": "component-missing-inherited",',
    '      "name": "Komponentenmethode ohne inherited",',
    '      "description": "Ein überschriebenes Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy oder Paint einer Komponente ruft inherited nicht auf; die VCL überspringt dann ihre eigene A' +
    'rbeit. Paint wird nur gemeldet, wenn das Paint eines Vorfahren selbst zeichnet (TCustomPanel, TImage, ein Grid oder eine Klasse aus Datei oder Index, die Paint deklariert), mit mittlerer Konfidenz; TC' +
    'ustomForm und TPaintBox lösen zur Laufzeit nur OnPaint aus, dort zählt ein Paint ohne inherited nur, wenn die Unit OnPaint benutzt oder eine Formulardatei hat; TCustomControl.Paint und TGraphicControl' +
    '.Paint sind leer, dort ist ein Paint ohne inherited üblich."',
    '    },',
    '{',
    '      "id": "component-default-mismatch",',
    '      "name": "default passt nicht zum Konstruktor",',
    '      "description": "Eine Eigenschaft gibt einen default-Wert an, der Konstruktor setzt das Feld aber auf ein anderes Literal. Werte gleich default speichert die DFM nicht, deshalb wird die Eigenscha' +
    'ft falsch geladen."',
    '    },',
    '{',
    '      "id": "component-missing-free-notification",',
    '      "name": "Komponentenreferenz ohne FreeNotification",',
    '      "description": "Eine Eigenschaft verweist auf eine andere Komponente, ihr Setter ruft aber FreeNotification nicht auf. Wird die andere Komponente freigegeben, bleibt ein ungültiger Zeiger zurück' +
    '. Im Konstruktor erzeugte Unterkomponenten sind ausgenommen."',
    '    },',
    '{',
    '      "id": "component-setter-without-invalidate",',
    '      "name": "Setter ohne Invalidate",',
    '      "description": "Ein Setter ändert ein Feld, das Paint liest, ruft aber weder Invalidate noch Repaint, Refresh oder Changed auf. Das Steuerelement zeigt weiter den alten Zustand."',
    '    },',
    '{',
    '      "id": "component-fixed-pixels",',
    '      "name": "Feste Pixelwerte",',
    '      "description": "Paint oder Resize verwenden feste Pixelwerte, die über 96 dpi zu klein sind. Werte über ScaleValue oder MulDiv oder über eine Methode der Klasse, die selbst skaliert (ruft ScaleV' +
    'alue, MulDiv oder eine Routine Scale… auf), 0, 1 und -1 sowie Faktoren von Multiplikationen und Divisionen werden nicht gemeldet."',
    '    },',
    '{',
    '      "id": "component-hardcoded-color",',
    '      "name": "Feste Farbe in Paint",',
    '      "description": "Paint verwendet ein RGB-Literal, eine $00BBGGRR-Konstante oder einen TColor-Cast. Solche Farben ignorieren VCL-Styles; Systemfarben wie clBtnFace sind in Ordnung."',
    '    },',
    '{',
    '      "id": "component-palette-icon",',
    '      "name": "Registrierte Komponente ohne Palettensymbol",',
    '      "description": "Jede an RegisterComponents übergebene Klasse braucht in einer per {$R} eingebundenen .dcr oder .res eine Bitmap mit dem Klassennamen in Großbuchstaben. Ab Delphi 11 werden zusätz' +
    'lich die Größen 16, 24 und 32 px (NAME16, NAME24, NAME32) erwartet. Ohne lesbare eingebundene Ressourcendatei schweigt die Regel."',
    '    }');

implementation

end.
