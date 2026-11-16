#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <stdio.h>

int main(int argc, char **argv) {
    setuid(0);
    setgid(0);
    if (argc < 2) return 1;

    const char *action = argv[1];
    int turnOn = (strcmp(action, "on") == 0);
    int turnOff = (strcmp(action, "off") == 0);
    if (!turnOn && !turnOff) return 1;

    DIR *dir = opendir("/Applications/iFile.app");
    if (dir) {
        struct dirent *ent;
        while ((ent = readdir(dir)) != NULL) {
            // Match any file starting with "iFile" (e.g. iFile, iFile2..5, iFile_, iFile6, etc.)
            if (strncmp(ent->d_name, "iFile", 5) == 0) {
                char fullpath[256];
                snprintf(fullpath, sizeof(fullpath), "/Applications/iFile.app/%s", ent->d_name);
                struct stat st;
                if (stat(fullpath, &st) == 0 && S_ISREG(st.st_mode)) {
                    mode_t newMode = turnOn ? (st.st_mode & ~S_ISUID) : (st.st_mode | S_ISUID);
                    chmod(fullpath, newMode);
                }
            }
        }
        closedir(dir);
    }

    // Terminate any running iFile instance cleanly so kernel reloads binary with new permission state
    system("killall -9 iFile iFile_ iFile5 iFile4 iFile3 iFile2 2>/dev/null");
    return 0;
}
