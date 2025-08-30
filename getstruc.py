import os

def print_tree(root_path, prefix=""):
    # List directories and files separately
    items = sorted(os.listdir(root_path))
    pointers = ['├── '] * (len(items) - 1) + ['└── ']

    for pointer, item in zip(pointers, items):
        path = os.path.join(root_path, item)
        print(prefix + pointer + item)
        if os.path.isdir(path):
            extension = '│   ' if pointer == '├── ' else '    '
            print_tree(path, prefix + extension)

if __name__ == "__main__":
    # Change '.' to any path you want to inspect
    root_dir = "."
    print(os.path.basename(os.path.abspath(root_dir)))
    print_tree(root_dir)
