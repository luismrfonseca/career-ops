import fs from 'fs';
import path from 'path';

const PIPELINE_PATH = path.join(process.cwd(), 'data/pipeline.md');

function extractUrls() {
  try {
    const content = fs.readFileSync(PIPELINE_PATH, 'utf8');
    const lines = content.split('\n');
    
    let inPendingSection = false;
    const urls = [];

    for (const line of lines) {
      if (line.match(/^##\s+(Pending|Pendientes)/i)) {
        inPendingSection = true;
        continue;
      }
      
      if (inPendingSection && line.startsWith('## ')) {
        // Entered another section
        break;
      }

      if (inPendingSection) {
        // Match unchecked items: - [ ] URL ... or - [ ] [Company](URL)
        // The format in the file is: - [ ] https://... | Company | Role
        const match = line.match(/^-\s*\[\s*\]\s*(?:\[[^\]]+\]\()?(https?:\/\/[^\s|)]+)/);
        if (match) {
          urls.push(match[1]);
        }
      }
    }

    if (urls.length > 0) {
      process.stdout.write(urls.join('\n') + '\n');
    }
  } catch (error) {
    console.error(`Error reading pipeline: ${error.message}`);
    process.exit(1);
  }
}

extractUrls();
