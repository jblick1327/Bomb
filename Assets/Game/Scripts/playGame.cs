using System;
using UnityEngine;
using UnityEngine.SceneManagement;

public class playbutton : MonoBehaviour
{
    public void playGame()
    {
        SceneManager.LoadScene("Arena");
        Debug.Log("PLAY BUTTON PRESSED");
    }
}